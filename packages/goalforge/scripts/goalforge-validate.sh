#!/usr/bin/env bash
# goalforge-validate.sh — authoritative SDD status reader + integrity validator.
#
# Usage:
#   goalforge-validate.sh [--strict] [--require-commit] [--quiet] [--stale-days N] [<plans-dir>]
#
# Walks <plans-dir> (default: ~/.claude/plans) for .md files with YAML
# frontmatter. For each file: checks required fields, enum values, then
# enforces the SDD integrity invariants from spec §6 / schema.md:
#
#   1. status:verified  ⇒ every sibling task-*.md is verified
#                         AND findings.md exists in the same folder.
#   2. status:executing ⇒ ≥1 sibling task-*.md has a `checkpoint:` block.
#   3. depends_on: [x]  ⇒ x exists (by name: field) and is dep-satisfying: `ready`+
#                         for a WP dep, plus `archived` (WP_DEP_SATISFIED); the TASK
#                         dep gate keeps its own set (`ready`+ ∪ implemented/verified).
#   4. stage_updated older than N days on non-terminal status → WARN (staleness).
#
# Flags:
#   --strict           Exit non-zero if any ERROR (not just WARN) is found.
#                      Enforces stale-rollup as ERROR; does NOT enforce missing commit.
#   --require-commit   Also exit non-zero when any verified task is missing its
#                      `commit:` hash. Use only at verify-time (goalforge-verify gate),
#                      NOT in the pre-commit hook (which would false-block the very
#                      commit that records the hash).
#                      A task whose deliverable is intentionally un-committable opts
#                      out with `commit_exempt: <prose reason>` in its own frontmatter:
#                      the missing hash becomes a WARN that prints the reason on every
#                      run. Empty / boolean-ish values, and a commit_exempt: alongside a
#                      real `commit:`, are ERRORs — the gate fails closed.
#   --quiet            Print one-line summary only; always exits 0.
#   --stale-days N     Override staleness threshold (default 30).
#
# NEVER rewrites any file. Only reports + suggests fixes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
GOAL_HASH_SH="$SCRIPT_DIR/goalforge-goal-hash.sh"

# ── Argument parsing ────────────────────────────────────────────────────────

STRICT=0
REQUIRE_COMMIT=0
QUIET=0
STALE_DAYS=30
FEATURE=""
SHOW=0
LIST_STATUS=""
SELFTEST=0
# No explicit arg yet — sentinel so we can detect "user passed a path" below.
PLANS_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)          STRICT=1; shift ;;
        --require-commit)  REQUIRE_COMMIT=1; shift ;;
        --quiet)           QUIET=1; shift ;;
        --stale-days)      STALE_DAYS="$2"; shift 2 ;;
        --feature)         FEATURE="$2"; shift 2 ;;
        --show)            SHOW=1; shift ;;
        --list-status)     LIST_STATUS="$2"; shift 2 ;;
        --self-test)       SELFTEST=1; shift ;;
        -*)                echo "Unknown flag: $1" >&2; exit 1 ;;
        *)                 PLANS_DIR="$1"; shift ;;
    esac
done

# ── Self-test: evolved-goal re-harden gate (self-contained fixtures) ─────────
# Builds a clean feature+WP in a temp dir, stamps the approved hash via the
# single authority (goalforge-goal-hash.sh), then asserts: (a) a matching goal block
# validates clean; (b) a goal block mutated after approval is flagged
# `evolved-goal` (ERROR under --strict). Exit 0 iff both expectations hold.
goalforge_self_test() {
    local t_pass=0 t_fail=0 pr feat wp out rc
    local tmp; tmp="$(mktemp -d)"
    trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"' EXIT
    pr="$tmp/plans"; feat="$pr/tmpfeat"; wp="$feat/wp-01-x"
    mkdir -p "$wp"

    cat > "$feat/overview.md" <<'EOF'
---
name: tmpfeat
title: Evolved-goal self-test
status: ready
created: 2026-06-23
feature: tmpfeat
work_packages: [wp-01-x]
---

# fixture feature
EOF
    cat > "$wp/overview.md" <<'EOF'
---
name: wp-01-x
title: Self-test WP
status: ready
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
task_type: code
goal:
  outcome: "the thing is done"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: null
---

# self-test wp
EOF

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL"; t_fail=$((t_fail+1)); }

    echo "=== goalforge-validate.sh --self-test (evolved-goal) ==="

    # Stamp the approved hash through the single authority.
    bash "$GOAL_HASH_SH" --record "$wp" >/dev/null

    # (a) goal block matches its approved hash → no evolved-goal error, exit 0.
    out="$(bash "$SELF" --strict --show "$pr" 2>&1)"; rc=$?
    if [[ "$rc" -eq 0 ]] && ! echo "$out" | grep -qi 'evolved-goal'; then
        ok "evolved-goal-clean"
    else
        echo "$out" >&2; no "evolved-goal-clean (rc=$rc)"
    fi

    # (b) mutate the goal block AFTER approval → evolved-goal ERROR, exit non-zero.
    python3 - "$wp/overview.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("the thing is done", "the thing is DONE-NOW"))
PY
    out="$(bash "$SELF" --strict --show "$pr" 2>&1)"; rc=$?
    if [[ "$rc" -ne 0 ]] && echo "$out" | grep -qi 'evolved-goal'; then
        ok "evolved-goal-detected"
    else
        echo "$out" >&2; no "evolved-goal-detected (rc=$rc)"
    fi

    # ── non-hash-stamp cases (rewrite the single fixture WP, so the whole-dir scan
    #    sees ONLY this WP → assertions need no per-WP line correlation) ──────────
    # helper: rewrite $wp/overview.md at a given status with a FREE-FORM (non-hash)
    # goal_approved_version. Goal block stays complete + internally consistent.
    _write_nhs_wp() {  # $1 = status
        cat > "$wp/overview.md" <<EOF
---
name: wp-01-x
title: Self-test WP
status: $1
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
task_type: code
goal:
  outcome: "the thing is done"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: "approved-v1"
---

# self-test wp
EOF
    }

    # (c) a non-hash stamp is flagged at a BELOW-ready status (unconditional on
    #     status — the old ready+ filter would have skipped it), ERROR under --strict.
    _write_nhs_wp hardened
    out="$(bash "$SELF" --strict --show "$pr" 2>&1)"; rc=$?
    if [[ "$rc" -ne 0 ]] && echo "$out" | grep -q 'non-hash-stamp'; then
        ok "non-hash-stamp-unconditional"
    else
        echo "$out" >&2; no "non-hash-stamp-unconditional (rc=$rc)"
    fi

    # (d) at ready: non-hash-stamp FIRES and evolved-goal-without-reharden does NOT
    #     (distinctness — a garbage stamp is one error, not two).
    _write_nhs_wp ready
    out="$(bash "$SELF" --strict --show "$pr" 2>&1)"; rc=$?
    if echo "$out" | grep -q 'non-hash-stamp' && ! echo "$out" | grep -qi 'evolved-goal'; then
        ok "non-hash-stamp-distinct-from-evolved"
    else
        echo "$out" >&2; no "non-hash-stamp-distinct-from-evolved (rc=$rc)"
    fi

    # ── Monotonicity cases (isolated plans root — independent of evolved-goal) ──
    # A coherent WP (spec + a pending task) must NOT trip the check; a zombie WP
    # (spec with all child tasks verified) MUST be flagged `status-monotonicity`.
    local mono_pr mono
    mono_pr="$tmp/monoplans"; mono="$mono_pr/monofeat"
    mkdir -p "$mono/wp-01-coh" "$mono/wp-02-zom"

    cat > "$mono/overview.md" <<'EOF'
---
name: monofeat
title: Monotonicity self-test
status: ready
created: 2026-06-23
feature: monofeat
work_packages: [wp-01-coh, wp-02-zom]
---

# fixture feature
EOF
    cat > "$mono/wp-01-coh/overview.md" <<'EOF'
---
name: wp-01-coh
title: Coherent WP
status: spec
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: monofeat
---

# coherent wp
EOF
    cat > "$mono/wp-01-coh/task-01-coh.md" <<'EOF'
---
name: task-01-coh
title: pending task
status: pending
verify: "true"
---

# pending
EOF
    cat > "$mono/wp-02-zom/overview.md" <<'EOF'
---
name: wp-02-zom
title: Zombie WP
status: spec
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: monofeat
---

# zombie wp
EOF
    cat > "$mono/wp-02-zom/task-01-zom.md" <<'EOF'
---
name: task-01-zom
title: verified task
status: verified
verify: "true"
commit: abc1234
---

# verified
EOF

    out="$(bash "$SELF" --strict --show "$mono_pr" 2>&1)"; rc=$?
    # (a) coherent WP (spec + pending task) raises no monotonicity error
    if echo "$out" | grep -i 'monoton' | grep -q 'wp-01-coh'; then
        echo "$out" >&2; no "monotonicity-coherent-clean"
    else
        ok "monotonicity-coherent-clean"
    fi
    # (b) zombie WP (spec, all tasks verified) is flagged (ERROR under --strict)
    if [[ "$rc" -ne 0 ]] && echo "$out" | grep -i 'monoton' | grep -q 'wp-02-zom'; then
        ok "monotonicity-zombie-detected"
    else
        echo "$out" >&2; no "monotonicity-zombie-detected (rc=$rc)"
    fi

    # ── verify-path existence + verb command -v lint (isolated plans root) ──────
    # wp-06 task-01: file-path tokens parsed out of each VERIFIED task's verify:
    # string must exist (high-confidence missing → ERROR; tmp/ evidence → WARN);
    # the first verb token is command -v'd (WARN if not on PATH, NEVER executed).
    # Fixtures mirror the real task frontmatter shape (name/title/status/verify) so
    # the branches fire against the real schema, not a divergent fixture shape.
    # vroot is the PROJECT ROOT; vpr=$vroot/plans makes verify_base resolve to
    # $vroot (parent of plans/) — so fixture verify-paths are deterministically
    # missing under it regardless of the invoking CWD.
    local vroot vpr vfeat vwp vout vrc
    vroot="$tmp/vroot"; vpr="$vroot/plans"; vfeat="$vpr/vfeat"; vwp="$vfeat/wp-01-vp"
    mkdir -p "$vwp"

    cat > "$vfeat/overview.md" <<'EOF'
---
name: vfeat
title: Verify-lint self-test
status: active
created: 2026-06-23
---

# fixture feature
EOF
    cat > "$vwp/overview.md" <<'EOF'
---
name: wp-01-vp
title: Verify-lint WP
status: verified
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: vfeat
---

# verify-lint wp
EOF
    echo "# findings" > "$vwp/findings.md"   # invariant 1: verified WP needs findings.md

    # (a) VERIFIED task: verify: names a high-confidence missing path → ERROR.
    #     Path sits under an allowlisted/tracked dir (skills/) so it is NOT gitignored.
    cat > "$vwp/task-01-vmiss.md" <<'EOF'
---
name: task-01-vmiss
title: missing-path task
status: verified
commit: abc1234
verify: "test -f skills/__goalforge_missing_fixture__/x.sh"
---

# missing path
EOF
    # (b) VERIFIED task: verify: names a tmp/ evidence path → WARN (not ERROR).
    cat > "$vwp/task-02-vtmp.md" <<'EOF'
---
name: task-02-vtmp
title: tmp-evidence task
status: verified
commit: abc1234
verify: "test -f tmp/__goalforge_fixture__/evidence.txt"
---

# tmp evidence
EOF
    # (c) task whose verify: FIRST token is not on PATH → verb-lint WARN (never run).
    cat > "$vwp/task-03-vverb.md" <<'EOF'
---
name: task-03-vverb
title: bogus-verb task
status: verified
commit: abc1234
verify: "__goalforge_bogus_verb__ --self-test"
---

# bogus verb
EOF
    # (d) VERIFIED task whose verify: NEGATES a file test (asserts the path is GONE):
    #     references the SAME missing path as (a) but must NOT be ERROR'd — the
    #     contrast proves the skip keys on the negation structure, not the path.
    cat > "$vwp/task-04-vneg.md" <<'EOF'
---
name: task-04-vneg
title: negated-existence task
status: verified
commit: abc1234
verify: "! test -f skills/__goalforge_missing_fixture__/x.sh"
---

# negated existence (legitimate "artifact removed" assertion)
EOF
    # (e) VERIFIED task whose verify NAMES a still-present path (non-negated) but
    #     declares it expects_absent ⇒ ERROR (the deletion regressed). The present
    #     file is created under the fixture project root so it resolves.
    mkdir -p "$vroot/skills/__ea__"
    : > "$vroot/skills/__ea__/present.sh"
    cat > "$vwp/task-05-vea-present.md" <<'EOF'
---
name: task-05-vea-present
title: expects_absent but still present
status: verified
commit: abc1234
expects_absent:
  - skills/__ea__/present.sh
verify: "test -f skills/__ea__/present.sh"
---

# expects_absent present
EOF
    # (f) VERIFIED task whose verify NAMES a MISSING path (non-negated) declared
    #     expects_absent ⇒ NO finding (intended outcome). Without expects_absent this
    #     high-confidence missing .py would ERROR — the contrast proves suppression.
    cat > "$vwp/task-06-vea-missing.md" <<'EOF'
---
name: task-06-vea-missing
title: expects_absent and missing
status: verified
commit: abc1234
expects_absent:
  - skills/__ea__/gone.py
verify: "test -f skills/__ea__/gone.py"
---

# expects_absent missing
EOF

    # (g) VERIFIED task whose verify: suffixes a QUOTED shell var with a path
    #     (`"$b"/report.md`): the path fragment belongs to a shell-expanded word,
    #     never a literal file ⇒ NO verify-path finding.
    cat > "$vwp/task-07-vqvar.md" <<'EOF'
---
name: task-07-vqvar
title: quoted-var suffix task
status: verified
commit: abc1234
verify: 'diff "$a" "$b"/report.md'
---

# quoted var suffix
EOF
    # (h) VERIFIED task whose verify: names a SINGLE-STAR glob (`out/*.md`): a glob
    #     is a pattern, not a path ⇒ NO verify-path finding.
    cat > "$vwp/task-08-vglob.md" <<'EOF'
---
name: task-08-vglob
title: single-star glob task
status: verified
commit: abc1234
verify: "ls out/*.md"
---

# single-star glob
EOF
    # (i) GREEN-BOTH-WAYS guard: a QUOTED slash-containing grep PATTERN
    #     (`'src/foo'`) must stay dropped — unquoting it into a candidate is the
    #     forbidden regression ⇒ NO verify-path finding.
    cat > "$vwp/task-09-vqpat.md" <<'EOF'
---
name: task-09-vqpat
title: quoted slash pattern task
status: verified
commit: abc1234
verify: "grep -n 'src/foo' file"
---

# quoted slash pattern
EOF
    # (j) GREEN-BOTH-WAYS guard: `**` glob stays dropped ⇒ NO verify-path finding.
    cat > "$vwp/task-10-vdglob.md" <<'EOF'
---
name: task-10-vdglob
title: double-star glob task
status: verified
commit: abc1234
verify: "ls docs/**/*.md"
---

# double-star glob
EOF
    # (k) GREEN-BOTH-WAYS guard: a COMMENTED path reference is skipped line-wise;
    #     the live line names an existing fixture path ⇒ NO verify-path finding.
    cat > "$vwp/task-11-vcomment.md" <<'EOF'
---
name: task-11-vcomment
title: commented path reference task
status: verified
commit: abc1234
verify: |
  # docs/__gf_comment_skip__/note.md — commented reference, must be skipped
  test -f skills/__ea__/present.sh
---

# commented path reference
EOF
    # (l) VERIFIED task whose verify: opens a quoted span MID-WORD around a
    #     path-shaped segment (`--pattern='a X/leak.md b'`): shlex's non-posix
    #     tokenizer does NOT enter quote state for a mid-word quote, so the middle
    #     fragment arrives carrying no quote char — only the independent
    #     `_quoted_regions` overlap check drops it ⇒ NO verify-path finding.
    cat > "$vwp/task-12-vmidq.md" <<'EOF'
---
name: task-12-vmidq
title: mid-word-opened quoted span task
status: verified
commit: abc1234
verify: "grep -n --pattern='a skills/__gf_midq__/leak.md b' file"
---

# mid-word quoted span
EOF
    # (m) VERIFIED task whose verify: names an UNQUOTED shell expansion
    #     (`$GF_ROOT/...`): drop rule (b). Unguarded before this fixture — with the
    #     rule deleted the token takes the slash+known-ext ERROR branch.
    cat > "$vwp/task-13-vexpand.md" <<'EOF'
---
name: task-13-vexpand
title: unquoted expansion task
status: verified
commit: abc1234
verify: "test -f $GF_ROOT/references/tier-map.md"
---

# unquoted expansion
EOF
    # (n) VERIFIED task whose verify: names LITERAL `?` / `[` glob metacharacters:
    #     drop rule (c) beyond `*`. Unguarded before this fixture — narrowing (c)
    #     to `*` alone left the suite green.
    cat > "$vwp/task-14-vqglob.md" <<'EOF'
---
name: task-14-vqglob
title: question/bracket glob task
status: verified
commit: abc1234
verify: "ls skills/__gf_glob__/a[1].md skills/__gf_glob__/b?.md"
---

# question/bracket glob
EOF
    # (o) VERIFIED task whose verify: carries an UNBALANCED quote: shlex raises
    #     ValueError and the lexer degrades to "no candidates for this line".
    #     Pins BOTH halves — no traceback, and no verify-path finding.
    cat > "$vwp/task-15-vunbal.md" <<'EOF'
---
name: task-15-vunbal
title: unbalanced quote task
status: verified
commit: abc1234
verify: "test -f 'skills/__gf_unbal__/x.md"
---

# unbalanced quote
EOF
    # (p) VERIFIED task whose verify: names a path containing a literal APOSTROPHE
    #     alongside an unrelated missing path. Pins the drop as WORD-scoped: the
    #     apostrophe word is dropped (accepted false negative — "contains a quote
    #     char" is the proxy for "was quoted"), while the OTHER candidate on the
    #     same line still ERRORs. shlex does not raise on a mid-word quote, so
    #     nothing degrades line-wise.
    cat > "$vwp/task-16-vapos.md" <<'EOF'
---
name: task-16-vapos
title: literal apostrophe path task
status: verified
commit: abc1234
verify: "test -f skills/__gf_apos__/it's.md skills/__gf_apos__/real.md"
---

# literal apostrophe
EOF
    # (q) VERIFIED task whose verify: carries a QUOTED `! -f` (a grep PATTERN, not a
    #     negated file test): the negation skip runs on the quote-blanked copy, so
    #     the pattern must NOT suppress the unrelated missing path on that line
    #     ⇒ the path still ERRORs. Contrast with (d), where the negation is real.
    cat > "$vwp/task-17-vqneg.md" <<'EOF'
---
name: task-17-vqneg
title: quoted negation pattern task
status: verified
commit: abc1234
verify: "grep -q '! -f' skills/__gf_qneg__/real.md"
---

# quoted negation pattern
EOF

    # --show prints every finding and exits 0 (the message check is independent of
    # the exit code); a separate --strict run probes that the high-confidence ERROR
    # forces a non-zero exit. Isolating the two avoids conflating "message printed"
    # with "gated".
    vout="$(bash "$SELF" --show "$vpr" 2>&1)"
    bash "$SELF" --strict "$vpr" >/dev/null 2>&1; vrc=$?

    # (a) high-confidence missing path on a verified task ⇒ ERROR message AND, under
    #     --strict, a non-zero exit.
    if echo "$vout" | grep -i 'verify-path' | grep -q '__goalforge_missing_fixture__' \
        && [[ "$vrc" -ne 0 ]]; then
        ok "verify-path-missing-error"
    else
        echo "$vout" >&2; no "verify-path-missing-error (rc=$vrc)"
    fi

    # (b) tmp/ evidence path ⇒ WARN (verify-path branch, downgraded from ERROR)
    if echo "$vout" | grep -i 'verify-path' | grep -qi 'tmp/'; then
        ok "verify-path-tmp-warn"
    else
        echo "$vout" >&2; no "verify-path-tmp-warn"
    fi

    # (c) first verb token not on PATH ⇒ verb-lint WARN (string is NEVER executed)
    if echo "$vout" | grep -i 'verify-verb' | grep -q '__goalforge_bogus_verb__'; then
        ok "verb-lint-not-on-path"
    else
        echo "$vout" >&2; no "verb-lint-not-on-path"
    fi

    # (d) negated file-existence test ⇒ NO verify-path finding attributed to that task
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-04-vneg'; then
        echo "$vout" >&2; no "verify-path-negated-not-errored"
    else
        ok "verify-path-negated-not-errored"
    fi

    # (e) expects_absent path that STILL EXISTS ⇒ ERROR message AND --strict non-zero.
    if echo "$vout" | grep -i 'verify-path' | grep 'expects_absent' | grep -q 'present.sh' \
        && [[ "$vrc" -ne 0 ]]; then
        ok "expects-absent-present-error"
    else
        echo "$vout" >&2; no "expects-absent-present-error (rc=$vrc)"
    fi

    # (f) expects_absent path that is MISSING ⇒ NO finding attributed to that task.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-06-vea-missing'; then
        echo "$vout" >&2; no "expects-absent-missing-suppressed"
    else
        ok "expects-absent-missing-suppressed"
    fi

    # (g) quoted-var suffix (`"$b"/report.md`) ⇒ NO verify-path finding for that task.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-07-vqvar'; then
        echo "$vout" >&2; no "verify-path-quoted-var-suffix-not-errored"
    else
        ok "verify-path-quoted-var-suffix-not-errored"
    fi

    # (h) single-star glob (`out/*.md`) ⇒ NO verify-path finding for that task.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-08-vglob'; then
        echo "$vout" >&2; no "verify-path-single-star-glob-not-errored"
    else
        ok "verify-path-single-star-glob-not-errored"
    fi

    # (i) quoted slash-containing pattern stays dropped ⇒ NO verify-path finding.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-09-vqpat'; then
        echo "$vout" >&2; no "verify-path-quoted-pattern-still-dropped"
    else
        ok "verify-path-quoted-pattern-still-dropped"
    fi

    # (j) `**` glob stays dropped ⇒ NO verify-path finding.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-10-vdglob'; then
        echo "$vout" >&2; no "verify-path-double-star-glob-still-dropped"
    else
        ok "verify-path-double-star-glob-still-dropped"
    fi

    # (k) commented path reference skipped line-wise ⇒ NO verify-path finding.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-11-vcomment'; then
        echo "$vout" >&2; no "verify-path-comment-line-skipped"
    else
        ok "verify-path-comment-line-skipped"
    fi

    # (l) mid-word-opened quoted span ⇒ NO verify-path finding for that task.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-12-vmidq'; then
        echo "$vout" >&2; no "verify-path-midword-quoted-span-dropped"
    else
        ok "verify-path-midword-quoted-span-dropped"
    fi

    # (m) unquoted `$` expansion ⇒ NO verify-path finding for that task.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-13-vexpand'; then
        echo "$vout" >&2; no "verify-path-unquoted-expansion-dropped"
    else
        ok "verify-path-unquoted-expansion-dropped"
    fi

    # (n) literal `?` / `[` glob metacharacters ⇒ NO verify-path finding.
    if echo "$vout" | grep -i 'verify-path' | grep -q 'task-14-vqglob'; then
        echo "$vout" >&2; no "verify-path-question-bracket-glob-dropped"
    else
        ok "verify-path-question-bracket-glob-dropped"
    fi

    # (o) unbalanced quote ⇒ no traceback anywhere in the run AND no verify-path
    #     finding for that task (the ValueError degrade path).
    if echo "$vout" | grep -q 'Traceback (most recent call last)' \
        || { echo "$vout" | grep -i 'verify-path' | grep -q 'task-15-vunbal'; }; then
        echo "$vout" >&2; no "verify-path-unbalanced-quote-degrades"
    else
        ok "verify-path-unbalanced-quote-degrades"
    fi

    # (p) apostrophe word dropped BUT the unrelated candidate on the same line is
    #     still reported ⇒ the drop is word-scoped, not line-scoped.
    vapos="$(echo "$vout" | grep -i 'verify-path' | grep 'task-16-vapos')"
    if echo "$vapos" | grep -q '__gf_apos__/real.md' \
        && ! echo "$vapos" | grep -q "it's"; then
        ok "verify-path-apostrophe-drop-is-word-scoped"
    else
        echo "$vout" >&2; no "verify-path-apostrophe-drop-is-word-scoped"
    fi

    # (q) a QUOTED `! -f` pattern must not suppress the line ⇒ path still ERRORs.
    if echo "$vout" | grep -i 'verify-path' | grep 'task-17-vqneg' | grep -q '__gf_qneg__/real.md'; then
        ok "verify-path-quoted-negation-does-not-suppress"
    else
        echo "$vout" >&2; no "verify-path-quoted-negation-does-not-suppress"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

if [[ "$SELFTEST" -eq 1 ]]; then
    goalforge_self_test
    exit $?
fi

# Resolve PLANS_DIR when no explicit arg was given:
#   1. SDD_PLANS_DIR env var
#   2. <git-toplevel>/plans/ if inside a git repo, or <CWD>/plans/ if plans/ exists
#   3. ~/.claude/plans (global fallback)
if [[ -z "$PLANS_DIR" ]]; then
    if [[ -n "${SDD_PLANS_DIR:-}" ]]; then
        PLANS_DIR="$SDD_PLANS_DIR"
    else
        GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true
        if [[ -n "$GIT_ROOT" && -d "${GIT_ROOT}/plans" ]]; then
            PLANS_DIR="${GIT_ROOT}/plans"
        elif [[ -d "$(pwd)/plans" ]]; then
            PLANS_DIR="$(pwd)/plans"
        else
            PLANS_DIR="${HOME}/.claude/plans"
        fi
    fi
fi

# Resolve to absolute path
PLANS_DIR=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$PLANS_DIR" 2>/dev/null) || exit 1

if [ ! -d "$PLANS_DIR" ]; then
    # --quiet is a non-blocking session-end summary: a missing plans dir is a
    # silent no-op (exit 0), never an error. Only surface the error otherwise.
    if [ "$QUIET" = "1" ]; then
        exit 0
    fi
    echo "ERROR: plans dir not found: $PLANS_DIR" >&2
    exit 1
fi

# ── Delegate to Python for all YAML-aware logic ─────────────────────────────

python3 - "$PLANS_DIR" "$STRICT" "$QUIET" "$STALE_DAYS" "$REQUIRE_COMMIT" "$FEATURE" "$SHOW" "$LIST_STATUS" "$GOAL_HASH_SH" <<'PYEOF'
import sys
import os
import re
import subprocess
import shlex
from pathlib import Path
from datetime import date, timedelta

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not available. Install with: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

plans_dir      = Path(sys.argv[1])
strict         = sys.argv[2] == '1'
quiet          = sys.argv[3] == '1'
stale_days     = int(sys.argv[4])
require_commit = sys.argv[5] == '1'
feature        = sys.argv[6]
show           = sys.argv[7] == '1'
list_status    = sys.argv[8]
goal_hash_sh   = sys.argv[9] if len(sys.argv) > 9 else ''

today = date.today()

# Verify: file-path tokens are relative to the PROJECT ROOT — the parent of the
# top-level `plans/` dir (where skills/, hooks/, references/ live as siblings of
# plans/). Derive it from the walked plans_dir so resolution is independent of the
# CWD and of the git toplevel (which, in a monorepo/dotfiles layout, is NOT the
# project root: git-root=<repo>, project-root=<repo>/claude). Fall back to CWD when
# plans_dir carries no `plans` segment (e.g. an ad-hoc self-test fixture root).
def _project_root(pd, cwd):
    parts = pd.resolve().parts
    for i in range(len(parts) - 1, 0, -1):
        if parts[i] == 'plans':
            return Path(*parts[:i])
    return cwd

verify_base = _project_root(plans_dir, Path.cwd())
_verb_on_path_cache = {}

# ── Collectors ──────────────────────────────────────────────────────────────

errors         = []   # (file, message, suggestion)
warnings       = []   # (file, message)
fatal          = []   # goal-block schema violations — force non-zero exit regardless of --strict
drift          = []   # status-mirror drift — force non-zero exit regardless of --strict
commit_missing = []   # verified tasks with no commit: — force non-zero only under --require-commit

def err(filepath, msg, suggest=""):
    errors.append((str(filepath), msg, suggest))

def warn(filepath, msg):
    warnings.append((str(filepath), msg))

def commit_err(filepath, msg, suggest=""):
    """Missing commit-hash on a verified task.
    Under --require-commit: treated as an ERROR that forces non-zero exit.
    Otherwise: advisory WARN (exit 0) — the pre-commit hook must NOT use
    --require-commit, because commit: is recorded AFTER the task commit.
    NOT reached for a task carrying a valid `commit_exempt: <reason>` — that
    task's missing hash is a standing WARN naming the reason instead (see the
    verified-task block below). The exemption never silences the line."""
    if require_commit:
        errors.append((str(filepath), msg, suggest))
        commit_missing.append(str(filepath))
    else:
        warnings.append((str(filepath), msg))

def goal_err(filepath, msg, suggest=""):
    """A malformed goal block is a fatal schema violation (non-zero exit always)."""
    errors.append((str(filepath), msg, suggest))
    fatal.append(str(filepath))

def drift_err(filepath, msg, suggest=""):
    """A rendered Status mirror (Tasks/WP table cell) contradicting the canonical
    `status:` frontmatter. status: is the single source of truth — non-zero always."""
    errors.append((str(filepath), msg, suggest))
    drift.append(str(filepath))

# ── Schema constants ────────────────────────────────────────────────────────

# feature overview.md
FEATURE_STATUS_ENUM = {'draft','spec','ready','active','executing','completed','archived'}
FEATURE_REQUIRED    = {'name','title','status','created'}

# WP overview.md
WP_STATUS_ENUM   = {'draft','spec','hardened','ready','executing','verified','archived'}
WP_REQUIRED      = {'name','title','status','stage_updated'}

# task-NN-*.md
# `implemented` = deterministic eval passed + committed (interim, set by goalforge-execute);
# goalforge-verify promotes implemented → verified at the WP gate.
TASK_STATUS_ENUM = {'pending','briefed','in-progress','implemented','verified'}
TASK_REQUIRED    = {'name','title','status'}

# `commit_exempt:` must carry a PROSE reason naming why no commit can exist.
# These values normalize to a bare assertion rather than a reason and are
# rejected, so the marker cannot degrade into a blanket opt-out flag.
NON_REASONS      = {'true','false','yes','no','y','n','1','0',
                    'none','null','n/a','na','-'}

READY_PLUS = {'ready','executing','verified','completed','active'}  # "ready+" — dep satisfied
# WP-level only: `archived` is a second WP terminal set by an out-of-band edit — no
# goalforge script writes it to a WP (references/state-machine.md) — and it satisfies a
# WP dependency exactly as `verified` does. Deliberately NOT folded into READY_PLUS: the
# TASK dep check below also consumes READY_PLUS, and `archived` is not in
# TASK_STATUS_ENUM, so widening the shared constant would make the task dep gate go
# quiet on a status that is illegal for a task in the first place — masking the enum
# violation rather than reporting both.
WP_DEP_SATISFIED = READY_PLUS | {'archived'}
TERMINAL   = {'verified','archived','completed'}

# Goal layer (schema v4). The goal block is OPTIONAL; checked only when present.
STRATEGY_ENUM  = {'deterministic','numeric','judge','human'}
# WP rigor register (schema §WP frontmatter). Absent ⇒ production, always valid.
REGISTER_ENUM  = {'production','prototype'}
TASK_TYPE_ENUM = {'code','research','ops','writing','optimization','analysis','migration'}
NUMERIC_OPS    = {'<','<=','>','>=','==','!='}
SEVERITY_ENUM  = {'CRITICAL','HIGH','MEDIUM','LOW'}

# Verify-string lint (wp-06 task-01). A verify: token is a FILE PATH only if it
# contains '/' or ends in one of these extensions; bare command names, quoted
# grep patterns, flags, and ** globs are NOT paths. False-negative is safer than
# false-positive — an over-eager ERROR on a grep pattern would block an honest WP.
VERIFY_PATH_EXT = ('.sh', '.py', '.md', '.yaml', '.yml', '.json', '.toml', '.txt')

# ── Frontmatter parser ──────────────────────────────────────────────────────

class _YamlBroken(dict):
    """Sentinel: frontmatter delimiters present but the YAML failed to parse.
    A dict subclass so existing `.get()` callers degrade safely; carries `.msg`."""
    def __init__(self, msg):
        super().__init__()
        self.msg = msg

def parse_frontmatter(path: Path):
    """Return (fm_dict, has_checkpoint_block). On a genuine YAML parse failure
    returns (_YamlBroken(msg), False) — distinct from (None, False), which means
    no/garbled frontmatter delimiters."""
    try:
        text = path.read_text(encoding='utf-8')
    except OSError:
        return None, False
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        return None, False
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            end = i
            break
    if end is None:
        return None, False
    fm_text = '\n'.join(lines[1:end])
    try:
        fm = yaml.safe_load(fm_text) or {}
    except yaml.YAMLError as exc:
        return _YamlBroken(str(exc)), False
    # Detect checkpoint: block anywhere in the file (after frontmatter)
    body = '\n'.join(lines[end+1:])
    has_checkpoint = bool(re.search(r'^checkpoint:', body, re.MULTILINE))
    return fm, has_checkpoint

# ── Classify a .md file ─────────────────────────────────────────────────────

def classify(path: Path):
    """Return 'feature'|'spec'|'wp'|'task'|'other' based on filename conventions."""
    name = path.name
    if name == 'overview.md':
        # WP overview if parent folder looks like wp-NN-*
        if re.match(r'^wp-\d+', path.parent.name):
            return 'wp'
        return 'feature'
    if name == 'spec.md':
        return 'spec'           # feature-altitude goal block lives here (schema v4)
    if re.match(r'^task-\d+', name):
        return 'task'
    return 'other'

# ── Body + status-table helpers (drift detector) ────────────────────────────

def read_body(path: Path):
    """Return the file text after the YAML frontmatter block (or the whole text)."""
    try:
        text = path.read_text(encoding='utf-8')
    except OSError:
        return ''
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            return '\n'.join(lines[i+1:])
    return text

def _clean_cell(s: str):
    """Strip markdown formatting (backticks, bold/italic asterisks) + whitespace
    so a cell like `` `wp-01-x` `` matches the bare id `wp-01-x`."""
    return s.replace('`', '').replace('*', '').strip()

def parse_status_table(body: str, id_headers):
    """From the FIRST markdown table whose header has a 'status' column and an id
    column named in `id_headers`, yield (row_id, status_cell) for non-empty ids.
    Cells are markdown-stripped. Separator-row detected structurally so prose
    pipes don't false-match."""
    lines = body.split('\n')
    for i in range(len(lines) - 1):
        head = lines[i].strip()
        sep  = lines[i+1].strip()
        if not (head.startswith('|') and sep.startswith('|')):
            continue
        if set(sep) - set('|-: '):          # separator row is only | - : space
            continue
        headers = [c.strip().lower() for c in head.strip('|').split('|')]
        if 'status' not in headers:
            continue
        id_idx = next((j for j, h in enumerate(headers) if h in id_headers), None)
        if id_idx is None:
            continue
        status_idx = headers.index('status')
        out = []
        for k in range(i + 2, len(lines)):
            row = lines[k].strip()
            if not row.startswith('|'):
                break
            cells = [c.strip() for c in row.strip('|').split('|')]
            if len(cells) <= max(id_idx, status_idx):
                continue
            row_id, cell = _clean_cell(cells[id_idx]), _clean_cell(cells[status_idx])
            if row_id:
                out.append((row_id, cell))
        return out
    return []

# ── Walk the plans tree ─────────────────────────────────────────────────────

# Index: name → (path, fm) for dependency resolution
name_index = {}   # name_slug → (Path, dict)

all_files = []    # list of (Path, kind, fm, has_checkpoint)

# Eval scaffolding lives UNDER a plan (evals/fixtures/, evals/workspace/, …) and
# deliberately contains drifted/malformed plan files to exercise this very
# validator. Walking them yields false ERRORs. Skip any file whose path RELATIVE
# to the walked root has an `evals`/`workspace`/`results` component — but never
# the root itself, so passing a fixture dir AS the root (check-drift.sh) still works.
SCAFFOLD_DIRS = {'evals', 'workspace', 'results'}
# Archived plans are frozen historical records — not strict-validated when walking
# the full tree (they predate current schema and would yield noise that blocks
# commits touching plans/_archived/*). Pass an archived plan dir AS the root to
# validate it explicitly: parts[:-1] won't contain the marker when it's the root.
# ARCHIVE-DIRS: same set as goalforge-validate.sh / goalforge-stamp-tables.sh /
#   goalforge-status.sh / goalforge-plan-index.py -- keep in sync (no shared
#   constant: three of the four sites are quoted python heredocs with no importable module).
ARCHIVE_DIRS = {'_archived', '_archive'}
SKIP_DIRS = SCAFFOLD_DIRS | ARCHIVE_DIRS

for md_path in sorted(plans_dir.rglob('*.md')):
    if SKIP_DIRS & set(md_path.relative_to(plans_dir).parts[:-1]):
        continue
    kind = classify(md_path)
    if kind == 'other':
        continue
    fm, has_ckpt = parse_frontmatter(md_path)
    if isinstance(fm, _YamlBroken):
        err(md_path, f"invalid YAML frontmatter — {fm.msg.splitlines()[0]}",
            "fix the frontmatter; common cause: a double-quoted `verify:` scalar "
            "with `\\|` / `\\.` (invalid YAML escapes) — single-quote it or use a block scalar")
        continue
    if fm is None:
        continue
    all_files.append((md_path, kind, fm, has_ckpt))
    slug = fm.get('name', '')
    if slug:
        name_index[slug] = (md_path, fm)

# ── Archived-slug resolution index ──────────────────────────────────────────
# Edge targets (supersedes / superseded_by / depends_on) may point at a plan that
# goalforge-archive moved into _archived/. The main walk skips _archived/ (SKIP_DIRS) to
# avoid schema-validation noise — which also dropped archived slugs from
# name_index, causing false "target not found" ERRORs on every reference. Re-add
# archived plans to name_index by FEATURE SLUG only (never to all_files, so they
# are never field-validated). The slug is the directory name for a feature dir, or
# the `name:` field / file stem for a flat plan — legacy archived plans predate
# `name:` frontmatter, so the directory name is the authoritative slug. Archived
# plans were archived from `completed`, so they carry a synthetic `completed`
# status that satisfies depends_on resolution. Non-archived always takes precedence.
for _arch_name in ARCHIVE_DIRS:
    _arch_root = plans_dir / _arch_name
    if not _arch_root.is_dir():
        continue
    for _entry in sorted(_arch_root.iterdir()):
        if _entry.name.startswith('.'):
            continue
        if _entry.is_dir():
            _aslug = _entry.name
        elif _entry.suffix == '.md':
            _afm, _ = parse_frontmatter(_entry)
            _aslug = str(_afm['name']) if (_afm and 'name' in _afm) else _entry.stem
        else:
            continue
        if _aslug and _aslug not in name_index:
            name_index[_aslug] = (_entry, {'status': 'completed'})

# ── Projection mode: --list-status <enum> ────────────────────────────────────
# Emit feature-level slugs whose feature status == <enum>, one per line, exit 0.
# Pure projection: no validation, no integrity output. _archived/ is already
# excluded by the walk (SKIP_DIRS). Gated to kind == 'feature' so WP/task
# statuses never surface. This is the engine the goalforge-completed.sh detector wraps.
if list_status:
    for _p, _kind, _fm, _h in all_files:
        if _kind == 'feature' and str(_fm.get('status', '')) == list_status:
            print(_fm.get('name') or _p.parent.name)
    sys.exit(0)

# ── Validation passes ───────────────────────────────────────────────────────

def check_required(path, fm, required_fields):
    for field in required_fields:
        if field not in fm:
            err(path, f"missing required field `{field}`",
                f"Add `{field}:` to the frontmatter of {path.name}")

def check_enum(path, fm, field, enum):
    val = fm.get(field)
    if val is not None and val not in enum:
        err(path, f"`{field}: {val}` is not a valid status",
            f"Set `{field}:` to one of: {', '.join(sorted(enum))}")

def check_staleness(path, fm, status_val):
    if status_val in TERMINAL:
        return
    stage_upd = fm.get('stage_updated') or fm.get('updated')
    if not stage_upd:
        return
    try:
        upd_date = date.fromisoformat(str(stage_upd))
    except ValueError:
        return
    age = (today - upd_date).days
    if age > stale_days:
        warn(path, f"`stage_updated` is {age} days old (threshold: {stale_days}) "
                   f"and status is `{status_val}` — may be stale")

def resolve_dep_slug(raw):
    """Normalize a dep ref: unwrap 1-elem list, strip [[wikilink]] + quotes."""
    if isinstance(raw, list):
        raw = raw[0] if raw else ''
    return re.sub(r'^\[\[|\]\]$', '', str(raw)).strip().strip("'\"")

# supersedes/superseded_by are typically CROSS-FEATURE edges (the canonical case
# goalforge-archive writes: a new feature supersedes an old one). When the walked tree
# holds only one feature overview, a cross-feature target is legitimately out of
# scope — skip the existence check so single-feature validation never
# false-errors. When >=2 feature overviews are walked (e.g. the whole plans root,
# as goalforge-archive validates), a missing target is a real dangling-wikilink ERROR.
feature_count = sum(1 for _p, _k, _f, _h in all_files if _k == 'feature')

def check_supersede_edges(path, fm):
    """Existence-only resolution of supersedes/superseded_by relationship edges
    (no status requirement). Additive: legacy plans without these edges are a
    no-op. Guarded by feature_count to avoid false-danglers on single-feature
    validation of an inherently cross-feature edge."""
    if feature_count < 2:
        return
    for rel in (fm.get('relationships') or []):
        if not isinstance(rel, dict):
            continue
        for edge in ('supersedes', 'superseded_by'):
            if edge not in rel:
                continue
            tgt = rel[edge]
            for raw_t in (tgt if isinstance(tgt, list) else [tgt]):
                tslug = resolve_dep_slug(raw_t)
                if tslug and tslug not in name_index:
                    err(path,
                        f"`{edge}: {tslug}` — target not found in plans tree",
                        f"Check the {edge} wikilink target slug, or create the missing plan")

def check_goal_block(path, fm, kind):
    """Integrity-check the optional `goal:` block (schema v4). Absent ⇒ no-op.
    A malformed block is FATAL (goal_err → non-zero exit regardless of --strict)."""
    # task_type is independent of the goal block but shares the v4 enum.
    task_type = fm.get('task_type')
    if task_type is not None and task_type not in TASK_TYPE_ENUM:
        goal_err(path, f"`task_type: {task_type}` is not valid",
                 f"Use one of: {', '.join(sorted(TASK_TYPE_ENUM))}")

    # inherits_from (WP-only) must resolve to an existing feature spec slug.
    # A WP-scoped scan (root == a single WP dir) won't carry the parent feature in
    # name_index, so also resolve it on disk: the parent feature overview.md is the
    # WP folder's grandparent (plans/<feature>/<wp>/overview.md). This prevents a
    # false "feature spec not found" when validating one WP in isolation.
    if kind == 'wp':
        inh = fm.get('inherits_from')
        if inh and str(inh).lower() != 'null' and inh not in name_index:
            parent_overview = path.parent.parent / 'overview.md'
            parent_fm = None
            if parent_overview.exists():
                parent_fm, _ = parse_frontmatter(parent_overview)
            if not (parent_fm and parent_fm.get('name') == inh):
                goal_err(path, f"`inherits_from: {inh}` — feature spec not found in plans tree",
                         "Point inherits_from at an existing feature/spec slug, or use null")

    goal = fm.get('goal')
    if goal is None:
        return                      # legacy plan — no goal block, nothing to check
    if not isinstance(goal, dict):
        goal_err(path, "`goal:` must be a mapping (outcome/verification/...)",
                 "See schema.md → Goal object")
        return

    outcome = goal.get('outcome')
    if not (isinstance(outcome, str) and outcome.strip()):
        goal_err(path, "`goal.outcome` is empty or missing",
                 "Write one measurable sentence for goal.outcome")

    ver = goal.get('verification')
    if not isinstance(ver, dict):
        goal_err(path, "`goal.verification` must be a mapping (strategy + check)",
                 "Add goal.verification.{strategy, check}")
        return

    strat = ver.get('strategy')
    if strat not in STRATEGY_ENUM:
        goal_err(path, f"`goal.verification.strategy: {strat}` is not valid",
                 f"Use one of: {', '.join(sorted(STRATEGY_ENUM))}")
        return                      # downstream check-shape depends on a valid strategy

    check = ver.get('check')
    if strat in ('deterministic', 'human'):
        if not (isinstance(check, str) and check.strip()):
            goal_err(path, f"`{strat}` goal needs a non-empty string `check`",
                     "deterministic = a command; human = a gate prompt")
    elif strat == 'numeric':
        if not isinstance(check, dict):
            goal_err(path, "`numeric` goal `check` must be a mapping {bench, metric, op, threshold}")
        else:
            if not str(check.get('bench', '')).strip():
                goal_err(path, "`numeric` goal `check.bench` is empty")
            if not str(check.get('metric', '')).strip():
                goal_err(path, "`numeric` goal `check.metric` is empty")
            if check.get('op') not in NUMERIC_OPS:
                goal_err(path, f"`numeric` goal `check.op: {check.get('op')}` invalid",
                         f"Use one of: {', '.join(sorted(NUMERIC_OPS))}")
            thr = check.get('threshold')
            # bool is a subclass of int — reject it explicitly (a silently-wrong threshold).
            if isinstance(thr, bool) or not isinstance(thr, (int, float)):
                goal_err(path, "`numeric` goal `check.threshold` must be a number")
    elif strat == 'judge':
        if not isinstance(check, dict):
            goal_err(path, "`judge` goal `check` must be a mapping {artifact, rubric, block_on}")
        else:
            if not str(check.get('artifact', '')).strip():
                goal_err(path, "`judge` goal `check.artifact` is empty")
            if not str(check.get('rubric', '')).strip():
                goal_err(path, "`judge` goal `check.rubric` is empty")
            block_on = check.get('block_on')
            if not (isinstance(block_on, list) and block_on):
                goal_err(path, "`judge` goal `check.block_on` must be a non-empty list")
            elif any(s not in SEVERITY_ENUM for s in block_on):
                goal_err(path, f"`judge` goal `check.block_on` has an invalid severity",
                         f"Use only: {', '.join(sorted(SEVERITY_ENUM))}")

def check_evolved_goal(path, fm, status):
    """Evolved-goal re-harden gate (WP-only). A WP at ready+ carries the goal-block
    hash approved at the harden gate (`goal_approved_version`). If the goal block
    has since changed (recomputed hash != approved), the WP must be re-hardened.
    The hash is recomputed by the SINGLE authority `goalforge-goal-hash.sh` — never
    reimplemented here, so record and recompute can never diverge. A plain ERROR
    (gates under --strict), NOT fatal. Skipped when `goal_approved_version` is
    null/absent or the WP is below `ready`."""
    approved = fm.get('goal_approved_version')
    if approved is None:
        return
    approved_s = str(approved).strip().strip("'\"")
    if approved_s == '' or approved_s.lower() == 'null':
        return
    # non-hash-stamp gate (unconditional on status — checked BEFORE the ready+ filter):
    # a set-but-not-sha256[:12] goal_approved_version can never equal a recomputed
    # hash, so without this it would masquerade as `evolved-goal-without-reharden`
    # forever. Flag it as its OWN distinct plain ERROR, then RETURN so the
    # evolved-goal compare below never double-reports the same bad stamp.
    if not re.fullmatch(r'[0-9a-f]{12}', approved_s):
        err(path,
            f"non-hash-stamp: goal_approved_version '{approved_s}' is not sha256[:12]",
            f"Stamp only via the hash authority: goalforge-goal-hash.sh --record {path.parent.name}")
        return
    if status not in ('ready', 'executing', 'verified'):
        return
    if not goal_hash_sh or not os.path.exists(goal_hash_sh):
        return                      # degrade: hasher unavailable — never false-error
    try:
        res = subprocess.run(['bash', goal_hash_sh, str(path)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except OSError:
        return
    recomputed = (res.stdout or '').strip()
    if recomputed != approved_s:
        err(path,
            f"evolved-goal-without-reharden: goal changed after approval "
            f"(recompute {recomputed or '<none>'} != approved {approved_s})",
            f"Re-open for re-harden: goalforge-transition.sh {path.parent.name} hardened "
            f"--mode evidence --evidence <reharden-file> --reason 'goal evolved' "
            f"(evidence-gated from ready; template references/templates/reharden-evidence.md); "
            f"re-approval re-stamps goal_approved_version")

def check_goal_mandatory(path, fm, kind, status):
    """schema v5 goal-mandatory-at-ready: a WP whose frontmatter carries
    `schema_version:` >= 5 MUST have a `goal:` block once it reaches
    ready/executing/verified — the marker is a per-plan opt-in (schema.md
    "Version lineage"), strictly gated on its presence. Absent marker (legacy
    <=v4) is a no-op: the goal block stays optional, unchanged from v4. A
    missing goal block under the marker is FATAL (goal_err — non-zero exit
    regardless of --strict), matching the malformed-goal-block severity."""
    if kind != 'wp':
        return
    sv = fm.get('schema_version')
    if sv is None:
        return
    try:
        sv_num = int(sv)
    except (TypeError, ValueError):
        warn(path, f"`schema_version: {sv!r}` is not parseable as an integer — "
                    f"goal-mandatory check skipped")
        return   # malformed marker value — not this check's concern
    if sv_num < 5:
        return
    if status not in ('ready', 'executing', 'verified'):
        return
    if fm.get('goal') is None:
        goal_err(path,
            "schema_version >= 5: `goal:` block is mandatory at ready/executing/"
            "verified but is missing",
            "Add a complete goal: block (outcome/verification/constraints/"
            "boundaries/iteration_policy/blocked_stop) — see schema.md Goal object")

def check_register(path, fm, status, n_task_files):
    """`register:` integrity gate (adversarial-review M3). The field is
    execution-load-bearing — goalforge-execute Step 0 collapses a prototype WP to its
    single task's findings-doc commit — but sits OUTSIDE the goal hash (schema
    NB) and outside WP_REQUIRED (required-subset check passes unknown fields
    silently). This explicit check is the only mechanical gate on it.
    Absent ⇒ production, always valid (backward compatibility is the schema's
    own contract). All findings are plain ERRORs (gate under --strict), NOT
    fatal — same tier as evolved-goal/monotonicity.
      (a) value ∈ {production, prototype};
      (b) prototype ⇒ goal.verification.strategy ∈ {judge, human} — the spike
          verdict routes through the findings doc, never deterministic-on-
          spike-code (checked at any status: decompose stamps goal + register
          together, so a mismatch is malformed from birth);
      (c) prototype ⇒ exactly ONE task-*.md — checked at ready+ only, where the
          Step 0 collapse consumes it (a mid-authoring draft with 0 tasks must
          not false-block the pre-commit hook, which runs --strict)."""
    reg = fm.get('register')
    if reg is None:
        return
    reg_s = str(reg).strip()
    if reg_s not in REGISTER_ENUM:
        err(path, f"`register: {reg_s}` is not valid",
            f"Use one of: {', '.join(sorted(REGISTER_ENUM))} (absent = production)")
        return
    if reg_s != 'prototype':
        return
    strat = None
    goal = fm.get('goal')
    if isinstance(goal, dict):
        ver = goal.get('verification')
        if isinstance(ver, dict):
            strat = ver.get('strategy')
    if strat not in ('judge', 'human'):
        err(path,
            f"register-prototype: goal strategy `{strat}` — a prototype WP's "
            f"verdict must be judge|human (findings doc), never "
            f"deterministic-on-spike-code",
            "Set goal.verification.strategy to judge or human — see schema.md "
            "§WP frontmatter register NB")
    if status in ('ready', 'executing', 'verified') and n_task_files != 1:
        err(path,
            f"register-prototype: {n_task_files} task file(s) — a prototype WP "
            f"carries exactly ONE task (goalforge-execute Step 0 collapses the spike "
            f"to that task's findings-doc commit)",
            "Merge the spike into a single task-01-*.md, or split the extra "
            "work into a separate production WP")

def check_status_monotonicity(path, status, child_task_statuses):
    """WP/task status-monotonicity coherence — the deterministic backstop for the
    reverse-transition supersession model. A reverse transition keeps child tasks
    `verified` as superseded evidence (the ledger row is the supersession record;
    no task field changes). But a WP sitting at an EARLY status while EVERY child
    task is `verified` is a 'zombie': the backward move happened, yet nothing
    re-opened the evidence. Flag it (plain ERROR — gates under --strict; NOT fatal).
    Skipped when: zero tasks (a taskless WP is never a zombie — vacuous-true guard);
    status is `executing` (all-verified-at-executing is the legitimate pre-verify
    state goalforge-execute resolves by running goalforge-verify); status is `verified`; or any
    child task is non-`verified`."""
    if status not in ('draft', 'spec', 'hardened', 'ready'):
        return
    if not child_task_statuses:
        return                          # vacuous-true guard: no tasks ⇒ no zombie
    if all(s == 'verified' for s in child_task_statuses):
        n = len(child_task_statuses)
        err(path,
            f"status-monotonicity: WP at '{status}' but all {n} child task(s) are "
            f"verified (zombie state — reverse transition left tasks as superseded "
            f"evidence; re-open or re-verify)",
            "Advance the WP to `verified` if the work stands, or re-open the tasks "
            "(set them back to pending/in-progress) to match the WP's earlier status")

# ── verify: string lints (verify-path existence + verb command -v) ────────────
# NEVER executes the verify: string — verb-lint only RESOLVES the first token via
# `command -v`, and verify-path only stats file-path tokens.

def _first_verify_verb(verify):
    """First command token of a verify: string — skipping comment/blank lines, a
    leading `!`, and unwrapping a `VAR=$(cmd ...` command-substitution assignment."""
    for line in verify.splitlines():
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        toks = s.split()
        if toks and toks[0] == '!':
            toks = toks[1:]
        if not toks:
            continue
        tok = toks[0]
        m = re.match(r'^[A-Za-z_][A-Za-z0-9_]*=[$`]\(?(.+)$', tok)   # out=$(bash → bash
        if m:                           # (.+)$ guarantees group(1) is non-empty
            tok = m.group(1)
        if tok.startswith('$('):        # bare command-sub opener: $(bash …
            tok = tok[2:]
        elif tok.startswith('`'):       # bare backtick opener: `bash …
            tok = tok[1:]
        tok = tok.lstrip('(')           # leading subshell/group paren: (cd …
        if tok:
            return tok
    return None

def _verb_on_path(verb):
    """True iff `command -v <verb>` succeeds (PATH exe, builtin, or keyword). Runs
    command -v in a non-interactive bash — it RESOLVES the name, never executes the
    verify command. Degrades to True if bash is missing (never false-WARN). Memoised."""
    if verb in _verb_on_path_cache:
        return _verb_on_path_cache[verb]
    try:
        r = subprocess.run(['bash', '-c', 'command -v "$1"', '_', verb],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        ok = (r.returncode == 0)
    except (OSError, subprocess.TimeoutExpired):
        ok = True                       # degrade: never spuriously WARN on a slow/absent bash
    _verb_on_path_cache[verb] = ok
    return ok

def _quoted_regions(line):
    """Source spans of the CLOSED quoted regions of `line`, left-to-right scan.

    Independent of shlex: a quote opens a region wherever it occurs, including
    MID-WORD (`--pattern='a b c'`), which is exactly the case shlex's non-posix
    tokenizer does not treat as quoted. An unterminated trailing quote yields NO
    region — the drop must stay word-scoped, so a literal apostrophe
    (`it's/fine.md`) never suppresses the rest of the line (shlex does not raise
    on a mid-word quote, so the line is still tokenized).
    """
    regions, q, start = [], None, 0
    for i, ch in enumerate(line):
        if q is None:
            if ch in '"\'':
                q, start = ch, i
        elif ch == q:
            regions.append((start, i + 1))
            q = None
    return regions

def _shell_words(line):
    """Split a line into shell WORDS — `(word, start, end)` source spans — with
    quote provenance retained.

    `shlex.split(posix=False)` keeps the quote characters (that is the whole point
    — posix=True would UNQUOTE, turning a grep pattern `'src/foo'` into a path
    candidate). It enters quote state ONLY for a quote that STARTS a token; such a
    leading-quote span terminates the token at its closing quote, so
    `"$b"/report.md` comes back as `['"$b"', '/report.md']`. Re-merge adjacent
    tokens that had no whitespace between them, so a word carries the quotes of
    every span it contains. RESIDUAL: a quote that opens MID-word is an ordinary
    word character to shlex, so whitespace inside that span still splits the token
    and the re-merge cannot repair it — hence the caller also drops a word whose
    span overlaps a `_quoted_regions` span. On an unbalanced LEADING quote shlex
    raises ValueError — the caller yields nothing for that line rather than
    propagating.
    """
    words, cur = [], 0
    for tok in shlex.split(line, posix=False):
        i = line.index(tok, cur)
        if words and i == cur:
            words[-1] = (words[-1][0] + tok, words[-1][1], i + len(tok))
        else:
            words.append((tok, i, i + len(tok)))
        cur = i + len(tok)
    return words

def _verify_path_tokens(verify):
    """Yield FILE-PATH candidate tokens from a verify: string (ratified heuristic):
    drop comment/blank lines, then tokenize shell-aware and drop a word that
    (a) contains a quote char OR overlaps a quoted span of the line — the second
        clause catches a span opened MID-word, whose inner fragments carry no
        quote char at all (grep/sed patterns, --include='*.sh', --pattern='a b'),
    (b) contains `$` (shell expansion — not a literal path), or
    (c) contains a glob metacharacter (`*`, `?`, `[`) — a pattern, not a path.
    Keep a surviving token only if it contains '/' or ends in a known extension;
    skip flags (-x/--x). Token text stays byte-identical to the source word for
    unquoted literal paths (callers key on the exact text).

    NOTE for callers: a dropped word never reaches the caller, so NO dropped
    class is ever existence-checked — any `$VAR`-rooted path in a `verify:` is
    silently unchecked (a dangling `$VAR/suffix` reference goes undetected);
    verify: paths that must be gated should be literal repo-relative paths.
    Likewise an `expects_absent:` entry MUST be a literal path — a glob, a `$`
    expansion, a quoted span or a mid-word-opened quoted span there would
    silently never be enforced."""
    for line in verify.splitlines():
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        # Every span below is an offset into `s` (the STRIPPED line) — never the
        # raw `line`, whose indent under a `verify: |` block scalar would shift
        # them all and silently disable the overlap drop.
        regions = _quoted_regions(s)
        blanked = s
        for a, b in regions:      # length-preserving: offsets stay valid
            blanked = blanked[:a] + ' ' * (b - a) + blanked[b:]
        # A negated file test asserts NON-existence (`! test -f x`, `[ ! -f x ]`,
        # `! -d x`): the path is SUPPOSED to be gone, so never ERROR on it
        # (false-negative > false-positive). task-02 of this feature adds exactly
        # such a post-move dangling-reference check. Matched on the quote-blanked
        # copy so a quoted `! -f` (a grep PATTERN) cannot suppress the whole line.
        if re.search(r'!\s+(test\s+)?-[efds]\b', blanked):
            continue
        try:
            words = _shell_words(s)
        except ValueError:        # unbalanced quote — degrade, never raise
            continue
        for raw, w_start, w_end in words:
            if '"' in raw or "'" in raw:                   # (a) quote char
                continue
            if any(w_start < b and a < w_end for a, b in regions):   # (a) in a span
                continue
            if '$' in raw:                                 # (b) shell expansion
                continue
            if any(c in raw for c in '*?['):               # (c) glob pattern
                continue
            tok = raw.strip("()`;|&!<>").rstrip(',')
            if not tok or tok.startswith('-'):
                continue
            # A shell assignment (f=plans/x.md) carries the path in its RHS —
            # resolving the whole word would probe <root>/f=plans/x.md, a path
            # that can never exist, false-ERRORing every verified task that
            # binds a path to a variable. '=' before the first '/' is the
            # assignment shape; '=' later is part of a real path, left alone.
            head = tok.split('/', 1)[0]
            if '=' in head and not tok.startswith(('/', '~', '.')):
                tok = tok.split('=', 1)[1]
                if not tok:
                    continue
            if ('/' in tok) or tok.endswith(VERIFY_PATH_EXT):
                yield tok

def _verify_path_gitignored(tok):
    try:
        r = subprocess.run(['git', '-C', str(verify_base), 'check-ignore', '-q', '--', tok],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False

def check_verify_string(path, fm, status):
    """Lint a task's `verify:` string (never runs it).
      • verb-lint  — `command -v` the first verb token; WARN if not on PATH.
      • verify-path — file-path tokens must exist, but ONLY for a `verified` task:
        a WP must not reach verified on a STALE path (wp-06 goal); a pending/
        in-progress task legitimately references a not-yet-built artifact. High-
        confidence missing (slash + known ext) → ERROR; an ambiguous token, or a
        gitignored / tmp/ evidence path → WARN (false-negative safer than false-+)."""
    verify = fm.get('verify')
    if not isinstance(verify, str) or not verify.strip():
        return
    verb = _first_verify_verb(verify)
    if verb and not _verb_on_path(verb):
        warn(path, f"verify-verb `{verb}` not on PATH (command -v failed) — the "
                   f"`verify:` command may not run in a clean environment")
    if status != 'verified':
        return
    # expects_absent: paths a deletion task's verify legitimately asserts ABSENT.
    # For a listed token the existence check is INVERTED — exists → ERROR (the
    # deletion regressed), missing → pass. Unlisted tokens keep the logic below.
    ea = fm.get('expects_absent') or []
    if isinstance(ea, str):
        ea = [ea]
    expects_absent = {str(p) for p in ea}
    for tok in _verify_path_tokens(verify):
        tok_exp = os.path.expanduser(tok)
        if tok in expects_absent:
            target = Path(tok_exp) if os.path.isabs(tok_exp) else (verify_base / tok)
            if target.exists():
                err(path, f"verify-path `{tok}` is declared expects_absent but still exists (deletion did not happen / regressed)",
                    "Complete the deletion, or remove the path from expects_absent")
            continue   # missing → intended outcome → neither ERROR nor WARN
        if tok.startswith('tmp/') or '/tmp/' in tok:   # token filter never yields bare 'tmp'
            warn(path, f"verify-path `{tok}` is tmp/ evidence — uncommitted, may be absent at verify-time")
            continue
        target = Path(tok_exp) if os.path.isabs(tok_exp) else (verify_base / tok)
        if target.exists():
            continue
        if _verify_path_gitignored(tok):
            warn(path, f"verify-path `{tok}` is gitignored — evidence may be absent in a clean checkout")
            continue
        if ('/' in tok) and tok.endswith(VERIFY_PATH_EXT):
            err(path, f"verify-path `{tok}` does not exist (high-confidence missing file in a verified task's verify:)",
                "Fix the verify: path, or point it at the real artifact")
        else:
            warn(path, f"verify-path `{tok}` not found (ambiguous token — directory or bare filename)")

for path, kind, fm, has_ckpt in all_files:

    # ── verify-path existence + verb command -v lint (tasks carry `verify:`) ──
    check_verify_string(path, fm, str(fm.get('status', '')))

    # ── Field presence + enum checks ────────────────────────────────────────

    if kind == 'feature':
        check_required(path, fm, FEATURE_REQUIRED)
        check_enum(path, fm, 'status', FEATURE_STATUS_ENUM)
        status = fm.get('status', '')
        check_staleness(path, fm, status)
        check_goal_block(path, fm, kind)
        check_supersede_edges(path, fm)

        # ── Drift: feature "## Work Packages" table Status cell == WP status: ──
        feature_dir = path.parent
        for row_id, cell in parse_status_table(read_body(path), {'wp', 'work package'}):
            wp_ov = feature_dir / row_id / 'overview.md'
            if not wp_ov.exists():
                m = re.match(r'(wp-\d+)', row_id)
                cand = ([d for d in feature_dir.glob('wp-*')
                         if d.is_dir() and d.name.startswith(m.group(1))] if m else [])
                if not cand:
                    drift_err(path, f"WP table row `{row_id}` names no WP under {feature_dir.name}/",
                              "Fix the row id, or remove the dangling row")
                    continue
                wp_ov = cand[0] / 'overview.md'
            w_fm, _ = parse_frontmatter(wp_ov)
            w_status = str((w_fm or {}).get('status', ''))
            if cell and cell.lower() != w_status.lower():
                drift_err(path,
                          f"WP table Status `{cell}` for `{row_id}` != its overview status `{w_status}`",
                          "status: frontmatter is the source of truth — fix the table cell")

        # ── WARN-B: stale auto-generated feature rollup ──────────────────────
        # When todo.md has generated: true, its ## Status Rollup table MUST mirror
        # current WP status: values.  WARN-only; never changes exit code.
        _ftodo = feature_dir / 'todo.md'
        if _ftodo.exists():
            _ftodo_fm, _ = parse_frontmatter(_ftodo)
            if _ftodo_fm:
                _gen = _ftodo_fm.get('generated', False)
                if _gen is True or str(_gen).lower() == 'true':
                    _ftodo_body = read_body(_ftodo)
                    for _wp_id, _cell in parse_status_table(_ftodo_body, {'wp'}):
                        if not _cell:
                            continue
                        _wp_ov = feature_dir / _wp_id / 'overview.md'
                        if not _wp_ov.exists():
                            _m = re.match(r'(wp-\d+)', _wp_id)
                            if _m:
                                _cand = [d for d in feature_dir.glob('wp-*')
                                         if d.is_dir() and d.name.startswith(_m.group(1))]
                                if _cand:
                                    _wp_ov = _cand[0] / 'overview.md'
                        if not _wp_ov.exists():
                            continue
                        _wfm, _ = parse_frontmatter(_wp_ov)
                        if _wfm:
                            _ws = str(_wfm.get('status', ''))
                            if _cell.lower() != _ws.lower():
                                err(_ftodo,
                                    f"feature rollup todo.md Status Rollup cell '{_cell}' "
                                    f"for {_wp_id} != WP status '{_ws}' — stale; "
                                    f"regenerate with: goalforge-rollup.sh {feature_dir}")

    elif kind == 'spec':
        # Feature-altitude goal block (schema v4). Integrity-checked when present;
        # no required-field/enum checks (specs predate this and may omit them).
        check_goal_block(path, fm, kind)

    elif kind == 'wp':
        check_required(path, fm, WP_REQUIRED)
        check_enum(path, fm, 'status', WP_STATUS_ENUM)
        status = fm.get('status', '')
        check_staleness(path, fm, status)
        check_goal_block(path, fm, kind)
        check_evolved_goal(path, fm, status)
        check_goal_mandatory(path, fm, kind, status)
        check_supersede_edges(path, fm)

        wp_dir = path.parent

        # ── Child task statuses (gathered once; reused by the monotonicity check) ──
        _child_task_statuses = []
        for _t in sorted(wp_dir.glob('task-*.md')):
            _tfm, _ = parse_frontmatter(_t)
            if _tfm is None:
                continue
            _child_task_statuses.append(str(_tfm.get('status', '')))
        check_status_monotonicity(path, status, _child_task_statuses)
        check_register(path, fm, status, len(sorted(wp_dir.glob('task-*.md'))))

        # ── Drift: WP "## Tasks" table Status cell == the named task's status: ──
        for row_id, cell in parse_status_table(read_body(path), {'task'}):
            m = re.match(r'(task-\d+)', row_id)
            if not m:
                drift_err(path, f"Tasks table row id `{row_id}` is not a task-NN id",
                          "Use the task-NN form so the cell can be matched to its file")
                continue
            matches = [t for t in wp_dir.glob('task-*.md') if t.name.startswith(m.group(1))]
            if not matches:
                drift_err(path, f"Tasks table row `{row_id}` names no task file in {wp_dir.name}/",
                          "Fix the row id, or remove the dangling row")
                continue
            t_fm, _ = parse_frontmatter(matches[0])
            t_status = str((t_fm or {}).get('status', ''))
            if cell and cell.lower() != t_status.lower():
                drift_err(path,
                          f"Tasks table Status `{cell}` for `{row_id}` != task status `{t_status}`",
                          "status: frontmatter is the source of truth — fix the table cell")

        # ── Status-mirror smell: per-WP todo.md is a scratchpad, not a tracker ──
        todo = wp_dir / 'todo.md'
        if todo.exists():
            try:
                ttext = todo.read_text(encoding='utf-8')
            except OSError:
                ttext = ''
            if re.search(r'^\s*-\s*\[[ xX]\]\s*task-\d+', ttext, re.MULTILINE):
                warn(todo, "todo.md has `[ ] task-NN` status-mirror lines — per-WP todo is an "
                           "open-items scratchpad, not a status tracker (status: frontmatter is truth)")

            # ── WARN-A: verified WP whose todo.md still lists unresolved open-items ──
            # Fires on: unchecked checkbox (- [ ]) under ## Open Items or ## Blocked On,
            # OR any content bullet under ## Blocked On.  WARN-only; never changes exit code.
            if status == 'verified':
                _in_open   = False
                _in_block  = False
                _in_mlcmt  = False
                _warn_a    = False
                for _ln in ttext.split('\n'):
                    _s = _ln.strip()
                    if _in_mlcmt:
                        if '-->' in _s: _in_mlcmt = False
                        continue
                    if _s.startswith('<!--'):
                        if '-->' not in _s: _in_mlcmt = True
                        continue
                    if re.match(r'^#{1,6}\s+Open\s+Items\s*$', _s, re.IGNORECASE):
                        _in_open = True;  _in_block = False; continue
                    if re.match(r'^#{1,6}\s+Blocked\s+On\s*$', _s, re.IGNORECASE):
                        _in_open = False; _in_block = True;  continue
                    if re.match(r'^#{1,6}\s+', _s):
                        _in_open = False; _in_block = False; continue
                    if not (_in_open or _in_block) or not _s:
                        continue
                    if re.match(r'^-\s*<[^>]+>', _s):   # template placeholder bullet
                        continue
                    if re.match(r'^-\s*\[ \]', _s):     # unchecked checkbox — either section
                        _warn_a = True; break
                    if _in_block and re.match(r'^-\s+\S', _s):  # content bullet under Blocked On
                        _warn_a = True; break
                if _warn_a:
                    warn(todo, "WP is verified but todo.md still lists unresolved "
                               "open-items/blockers — reconcile (a verified WP has no "
                               "outstanding work) or regenerate")

        # ── Invariant 1: verified ⇒ all child tasks verified + findings.md ──
        if status == 'verified':
            wp_dir = path.parent
            task_files = sorted(wp_dir.glob('task-*.md'))
            for t in task_files:
                t_fm, _ = parse_frontmatter(t)
                if t_fm is None:
                    continue
                t_status = t_fm.get('status', '')
                if t_status != 'verified':
                    err(path,
                        f"WP is `verified` but task `{t.name}` has status `{t_status}`",
                        f"Either verify {t.name} first, or revert this WP's status")
            findings = wp_dir / 'findings.md'
            if not findings.exists():
                err(path,
                    f"WP is `verified` but `findings.md` is missing in {wp_dir.name}/",
                    f"Create `{findings}` with the verification evidence")

        # ── Invariant 2: executing ⇒ ≥1 task has checkpoint block ───────────
        elif status == 'executing':
            wp_dir = path.parent
            task_files = sorted(wp_dir.glob('task-*.md'))
            has_any_ckpt = False
            for t in task_files:
                _, t_ckpt = parse_frontmatter(t)
                if t_ckpt:
                    has_any_ckpt = True
                    break
            if task_files and not has_any_ckpt:
                err(path,
                    f"WP is `executing` but no task file contains a `checkpoint:` block",
                    f"Either set status back to `ready`, or run goalforge-execute to begin execution")

        # ── Invariant 3: depends_on resolution ──────────────────────────────
        raw_deps = fm.get('depends_on', []) or []
        # Also check relationships list
        for rel in (fm.get('relationships') or []):
            if isinstance(rel, dict) and 'depends_on' in rel:
                dep = rel['depends_on']
                raw_deps = list(raw_deps) + (dep if isinstance(dep, list) else [dep])

        for raw_dep in raw_deps:
            dep_slug = resolve_dep_slug(raw_dep)
            if not dep_slug:
                continue
            if dep_slug not in name_index:
                err(path,
                    f"`depends_on: {dep_slug}` — target not found in plans tree",
                    f"Check the slug spelling, or create the missing plan file")
            else:
                dep_path, dep_fm = name_index[dep_slug]
                dep_status = dep_fm.get('status', '')
                # Dependency READINESS is an execution-time precondition: only an
                # ERROR when this WP is itself claiming to be runnable (ready/
                # executing). A spec/draft WP whose dep is not yet ready is normal
                # pre-execution state — goalforge-execute orders the work at run time.
                # Existence of the target (checked above) is always enforced.
                if dep_status not in WP_DEP_SATISFIED and status in ('ready', 'executing'):
                    err(path,
                        f"`depends_on: {dep_slug}` exists but is `{dep_status}` "
                        f"(need ready/executing/verified/completed/active/archived)",
                        f"Advance {dep_slug} to `ready`+ (or `archived`) before this WP can proceed")

        # ── Invariant 3b: optional_depends_on — non-gating existence check ───
        # NEVER gates frontier/harden/execute: missing target is WARN only,
        # never ERROR, never affects exit code. Mirrors the depends_on lookup
        # above but skips the readiness/status gate entirely (existence-only).
        raw_opt_deps = fm.get('optional_depends_on', []) or []
        if isinstance(raw_opt_deps, str):
            raw_opt_deps = [raw_opt_deps]
        for rel in (fm.get('relationships') or []):
            if isinstance(rel, dict) and 'optional_depends_on' in rel:
                dep = rel['optional_depends_on']
                raw_opt_deps = list(raw_opt_deps) + (dep if isinstance(dep, list) else [dep])

        for raw_dep in raw_opt_deps:
            dep_slug = resolve_dep_slug(raw_dep)
            if not dep_slug:
                continue
            if dep_slug not in name_index:
                warn(path,
                     f"`optional_depends_on: {dep_slug}` — target not found in plans tree "
                     f"(non-gating; recorded for future propose-only surfacing only)")

    elif kind == 'task':
        check_required(path, fm, TASK_REQUIRED)
        check_enum(path, fm, 'status', TASK_STATUS_ENUM)
        status = fm.get('status', '')
        check_staleness(path, fm, status)

        # ── STATIC brief-skip invariant (wp-06) ──────────────────────────
        # A complexity-gated (medium/high) task that reached implemented/
        # verified WITHOUT a sibling brief-task-NN.md skipped the brief stage.
        # Static current-file-state check: complexity is read DIRECTLY from
        # this task's frontmatter (NOT goalforge-wp-complexity.sh), and no
        # transition/state-machine is observed. WARN (exit 0) — the brief
        # stage is new; this surfaces the skip without blocking --strict.
        task_complexity = str(fm.get('complexity', '') or '').strip().lower()
        if task_complexity in ('medium', 'high') and status in ('implemented', 'verified'):
            m = re.match(r'(task-\d+)', os.path.basename(str(path)))
            if m:
                # Canonical sibling is brief-<full-task-slug>.md (the name
                # execute/brief-staleness.sh resolves); the short
                # brief-task-NN.md form is accepted as legacy.
                task_slug = os.path.basename(str(path))[:-3]
                wp_dir = os.path.dirname(str(path))
                candidates = ('brief-%s.md' % task_slug,
                              'brief-%s.md' % m.group(1))
                if not any(os.path.exists(os.path.join(wp_dir, c))
                           for c in candidates):
                    warn(path,
                         'gated task (complexity=%s) at status `%s` has no '
                         'sibling brief-%s.md — brief stage was skipped'
                         % (task_complexity, status, task_slug))

        # Task-level depends_on within same WP
        raw_deps = fm.get('depends_on', []) or []
        for raw_dep in raw_deps:
            dep_slug = resolve_dep_slug(raw_dep)
            if not dep_slug:
                continue
            if dep_slug not in name_index:
                err(path,
                    f"`depends_on: {dep_slug}` — task not found",
                    f"Check the task slug spelling")
            else:
                dep_path, dep_fm = name_index[dep_slug]
                dep_status = dep_fm.get('status', '')
                # Only an ERROR when this task is actually being worked
                # (in-progress) — a pending task with a pending dep is normal
                # pre-execution state (goalforge-execute resolves ordering at run time).
                # Tasks use {pending, in-progress, implemented, verified}; a dep at
                # `implemented` is satisfied (its code is committed + deterministically
                # passing — it need not wait for the WP-gate promotion to verified).
                if (dep_status not in READY_PLUS
                        and dep_status not in ('verified', 'implemented')
                        and status == 'in-progress'):
                    err(path,
                        f"`depends_on: {dep_slug}` task has status `{dep_status}`",
                        f"Complete task {dep_slug} first")

        # ── Verified task must record its completing commit hash ─────────────────
        # WARN in plain run and under --strict alone (exit 0 unless other errors).
        # ERROR (non-zero exit) only under --require-commit.
        # Rationale: commit: is recorded AFTER the task commit, so the pre-commit
        # hook (which runs --strict) must NOT gate on it — that would false-block
        # the very commit that writes the hash.  goalforge-verify uses --strict
        # --require-commit to enforce the hash at verify-time only.
        #
        # ONE sanctioned exemption: a task whose deliverable is intentionally
        # un-committable (it writes only outside the repo, or only to a path the
        # repo gitignores by design) declares `commit_exempt: <prose reason>`.
        # The exemption is opt-in, per-task, reason-bearing, and never silent —
        # it downgrades the ERROR to a WARN that prints the reason every run.
        # goalforge-verify READS this key; it must never write it.
        if status == 'verified':
            commit_val = fm.get('commit', None)
            has_commit = bool(commit_val and str(commit_val).strip())
            exempt_raw = fm.get('commit_exempt', None)
            exempt     = '' if exempt_raw is None else str(exempt_raw).strip()
            exempt_ok  = bool(exempt) and exempt.lower() not in NON_REASONS

            if has_commit and exempt:
                err(path,
                    "task declares `commit_exempt:` AND carries a `commit:` hash — "
                    "the exemption asserts no commit can exist, the hash says one does",
                    "Drop commit_exempt: (the task WAS committed)")
            elif has_commit:
                pass
            elif exempt_ok:
                # Honoured exemption — downgraded, never suppressed.
                warn(path,
                     "verified task has no `commit:` — EXEMPT: " + exempt)
            elif exempt:
                commit_err(path,
                    "`commit_exempt:` is not a reason (got `" + exempt + "`) — the "
                    "exemption requires prose naming why no commit can exist",
                    "Replace with commit_exempt: <why this deliverable cannot be committed>")
            else:
                commit_err(path,
                    "verified task missing `commit:` (the completing commit hash) — "
                    "goalforge-execute records it after the task commit",
                    "Add commit: <sha>, re-run goalforge-execute, or — only if the "
                    "deliverable is intentionally un-committable — declare "
                    "commit_exempt: <reason>")

# ── Output ──────────────────────────────────────────────────────────────────

# ── --feature narrowing: filter reported issues to plans/<feature>/ ──────────
# The whole tree is still WALKED (edge resolution intact); only the REPORTED
# issues + the exit-determining counts are scoped to the named feature, so
# `--feature X --strict` answers "is feature X clean?" without other features'
# drift bleeding into its verdict.
if feature:
    feat_root = os.path.abspath(os.path.join(str(plans_dir), feature))
    def _in_feat(fp):
        ap = os.path.abspath(fp)
        return ap == feat_root or ap.startswith(feat_root + os.sep)
    errors         = [e for e in errors if _in_feat(e[0])]
    warnings       = [w for w in warnings if _in_feat(w[0])]
    fatal          = [f for f in fatal if _in_feat(f)]
    drift          = [d for d in drift if _in_feat(d)]
    commit_missing = [c for c in commit_missing if _in_feat(c)]

total_errors   = len(errors)
total_warnings = len(warnings)
scope          = f" [{feature}]" if feature else ""

# Three presentations:
#   --quiet : one-line summary, always exit 0 (session-end hook).
#   --show  : full ERROR/WARN dump (verbose, opt-in).
#   default : terse — one-line summary + the FIRST error (file:line + fix), then
#             a "run --show" note. Token-minimal; the leading ERROR line keeps
#             the pre-commit hook's `grep ^ERROR | head -1` diagnostic working.
if quiet:
    print(f"goalforge-validate{scope}: {total_errors} error(s), {total_warnings} warning(s) "
          f"— plans tree: {plans_dir}")
    sys.exit(0)

if show:
    if errors or warnings:
        for filepath, msg, suggest in errors:
            rel = os.path.relpath(filepath, str(plans_dir))
            print(f"ERROR  {rel}: {msg}")
            if suggest:
                print(f"       → {suggest}")
        for filepath, msg in warnings:
            rel = os.path.relpath(filepath, str(plans_dir))
            print(f"WARN   {rel}: {msg}")
    else:
        print(f"OK — {len(all_files)} plan file(s) validated in {plans_dir}")
elif errors or warnings:
    print(f"goalforge-validate{scope}: {total_errors} error(s), {total_warnings} warning(s) "
          f"(run --show to list)")
    if errors:
        filepath, msg, suggest = errors[0]
        rel = os.path.relpath(filepath, str(plans_dir))
        print(f"ERROR  {rel}: {msg}")
        if suggest:
            print(f"       → {suggest}")
else:
    print(f"OK — {feature} clean" if feature
          else f"OK — {len(all_files)} plan file(s) validated in {plans_dir}")

# Exit logic (three independent gates, any can force non-zero):
#   fatal          — malformed goal blocks; always fatal
#   drift          — status-mirror table cells contradicting frontmatter; always fatal
#   commit_missing — verified tasks missing commit: hash; fatal only under --require-commit
#   strict         — any other ERROR in errors[]; fatal under --strict
if fatal or drift or (require_commit and commit_missing):
    sys.exit(1)
if strict and total_errors > 0:
    sys.exit(1)
sys.exit(0)
PYEOF
