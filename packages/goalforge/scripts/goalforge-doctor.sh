#!/usr/bin/env bash
# goalforge-doctor.sh — install preflight: one command that says, deterministically,
# whether a goalforge install is usable.
#
# Usage:
#   goalforge-doctor.sh              run every check; exit 0 on green or
#                                    warnings-only, 1 on a hard failure
#   goalforge-doctor.sh --strict     promote warnings to failures (see the
#                                    exemption below); intended for the PLUGIN route
#   goalforge-doctor.sh --self-test  run the hermetic offline suite that proves
#                                    each failure arm actually fires
#   goalforge-doctor.sh --help       this text (printed before any check runs)
#
# Checks, in order (dep checks run FIRST so a later arm never reports a
# spurious failure caused by a missing tool):
#   1. hard deps        git python3 jq flock timeout realpath tar, plus PyYAML.
#                       `bash` is deliberately NOT probed: it is the running
#                       interpreter, not a dependency this script could survive
#                       the absence of.
#   2. bash major       < 4 is a WARNING (the stock macOS 3.2).
#   3. layout           the resolved root must carry SKILL.md and scripts/.
#   4. route + manifest PLUGIN route iff <root>/.claude-plugin/plugin.json exists.
#                       Plugin route: a missing, unreadable or dangling
#                       reference manifest is a HARD failure. Manual
#                       skills-dir route: an absent manifest is a WARNING and is
#                       EXEMPT from --strict promotion (the manifest is emitted
#                       plugin-side only, so promoting it would make --strict
#                       permanently red on a healthy manual install).
#   5. PLANS_ROOT       resolved through the ONE authority,
#                       hooks/goalforge-plans-root.sh — reported, never a failure.
#   6. git pre-commit   WARNING when absent INSIDE a git work tree; SKIPPED when
#                       the resolved root is not in one.
#
# Stable stderr tokens, one per arm, so a caller (and the self-test) can assert
# WHICH arm fired rather than only that the exit code was non-zero:
#   MISSING DEP: <name>   DANGLING REF: <path>   MANIFEST MISSING
#   BAD ROOT: <path>      WARN: <arm>            SKIPPED: <arm> (<why>)
#
# Exit codes:
#   0  green, or warnings only
#   1  at least one hard failure (or, under --strict, a promotable warning)
#   2  usage error
#
# Test-only environment seams (every one defaults self-relative, so consumer
# behaviour is unchanged when they are unset):
#   GF_DOCTOR_ROOT           tree under inspection      (default: this script's ..)
#   GF_DOCTOR_MANIFEST       manifest file              (default: <root>/references/reference-manifest.json)
#   GF_DOCTOR_BASH_VERSINFO  bash major version         (consulted BEFORE ${BASH_VERSINFO[0]},
#                                                        which is readonly and cannot be forced)
# CLAUDE_PLUGIN_ROOT is an OPTIONAL override that is REPORTED, never required:
# the host injects it only for plugin-declared hooks and commands, so it is
# unset in the plain shell a consumer runs this script from.
#
# Toolchain: bash builtins and `command -v` only. The manifest is parsed with
# python3, never with jq (jq is itself a checked dep — the missing-jq arm must
# not disable the reader), and roots are resolved with cd/pwd, never with
# realpath (also a checked dep).

set -uo pipefail

_src="${BASH_SOURCE[0]}"
case "$_src" in
    */*) _srcdir="${_src%/*}" ;;
    *)   _srcdir="." ;;
esac
SCRIPT_DIR="$(cd "$_srcdir" && pwd)"
SELF="$SCRIPT_DIR/${_src##*/}"

# The seven probed dependencies (spec §Design stream 5). `bash` is not one.
DEPS=(git python3 jq flock timeout realpath tar)

STRICT=0
FAILURES=0
WARNINGS=0          # promotable by --strict
EXEMPT=0            # warnings the exemption keeps out of --strict

fail()   { printf '%s\n' "$*" >&2; FAILURES=$(( FAILURES + 1 )); }
warn()   { printf 'WARN: %s\n' "$*" >&2; WARNINGS=$(( WARNINGS + 1 )); }
# A warning the consumer cannot act on: reported, never promoted by --strict.
warnx()  { printf 'WARN: %s\n' "$*" >&2; EXEMPT=$(( EXEMPT + 1 )); }
skip()   { printf 'SKIPPED: %s\n' "$*" >&2; }
ok()     { printf 'ok   %s\n' "$*"; }
note()   { printf '     %s\n' "$*"; }

have()   { command -v "$1" >/dev/null 2>&1; }

usage() {
    printf '%s\n' \
        'usage: goalforge-doctor.sh [--strict | --self-test | --help]' \
        '' \
        '  (no flags)    check deps, bash version, layout, reference manifest,' \
        '                PLANS_ROOT resolution and the git pre-commit hook.' \
        '                Exit 0 on green or warnings-only, 1 on a hard failure.' \
        '  --strict      promote warnings to failures. Intended for the plugin' \
        '                route; on the manual route the absent-manifest warning' \
        '                is exempt, because no manual install ever carries one.' \
        '  --self-test   run the hermetic offline suite proving each arm fires.' \
        '  --help        print this text and exit 0, before any check runs.'
}

# ---------------------------------------------------------------------------
# Arm 1 — hard dependencies (FIRST, so every later arm can gate on them)
# ---------------------------------------------------------------------------
check_deps() {
    local d
    for d in "${DEPS[@]}"; do
        if have "$d"; then
            ok "dep $d"
        else
            fail "MISSING DEP: $d"
        fi
    done
    if have python3; then
        if python3 -c 'import yaml' >/dev/null 2>&1; then
            ok "dep PyYAML"
        else
            fail "MISSING DEP: PyYAML (python3 -c 'import yaml')"
        fi
    else
        skip "pyyaml (missing python3)"
    fi
}

# ---------------------------------------------------------------------------
# Arm 2 — bash major version
# ---------------------------------------------------------------------------
check_bash_version() {
    # ${BASH_VERSINFO[0]} of the RUNNING shell is readonly, so the seam is the
    # only way to exercise the macOS-3.2 arm.
    local major="${GF_DOCTOR_BASH_VERSINFO:-${BASH_VERSINFO[0]}}"
    case "$major" in
        ''|*[!0-9]*) warn "bash<4 (unreadable major version: $major)"; return ;;
    esac
    if [ "$major" -lt 4 ]; then
        warn "bash<4 (found $major; goalforge scripts assume bash 4+)"
    else
        ok "bash major $major"
    fi
}

# ---------------------------------------------------------------------------
# Arm 3 — layout of the resolved root. Runs BEFORE the plans-root helper is
# sourced: a root that fails this has no hooks/ to source, and a `source` of a
# missing file must never be how the doctor reports a bad root.
# ---------------------------------------------------------------------------
check_layout() {
    if [ ! -d "$ROOT" ]; then
        fail "BAD ROOT: $ROOT (not a directory)"
        return 1
    fi
    if [ ! -f "$ROOT/SKILL.md" ] || [ ! -d "$ROOT/scripts" ]; then
        fail "BAD ROOT: $ROOT (expected SKILL.md and scripts/)"
        return 1
    fi
    ok "layout $ROOT"
    return 0
}

# ---------------------------------------------------------------------------
# Arm 4 — route discrimination + reference manifest
# ---------------------------------------------------------------------------
detect_route() {
    # Artifact shape, never manifest absence: absence is exactly what a
    # truncated plugin install looks like, and that is the defect this script
    # exists to catch.
    if [ -f "$ROOT/.claude-plugin/plugin.json" ]; then
        ROUTE=plugin
    else
        ROUTE=manual
    fi
    ok "route $ROUTE"
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        note "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} (optional override, reported only)"
    else
        note "CLAUDE_PLUGIN_ROOT unset (optional; the host sets it only for plugin hooks/commands)"
    fi
}

# read_manifest <manifest> <root> — print one diagnostic line per problem.
# Exit 0 clean, 3 unreadable/malformed, 4 bad schema, 5 dangling refs found.
read_manifest() {
    GF_DOC_MF="$1" GF_DOC_RT="$2" python3 - <<'PYEOF'
import json, os, sys

mf = os.environ["GF_DOC_MF"]
rt = os.path.abspath(os.environ["GF_DOC_RT"])
try:
    with open(mf, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:                                    # noqa: BLE001
    print("unreadable: %s" % (exc,))
    sys.exit(3)
if not isinstance(data, dict) or data.get("schema") != 1:
    print("schema: expected 1, found %r" % (data.get("schema") if isinstance(data, dict) else None,))
    sys.exit(4)
refs = data.get("refs")
if not isinstance(refs, list):
    print("schema: 'refs' is not a list")
    sys.exit(4)
bad = []
for entry in refs:
    path = entry.get("path") if isinstance(entry, dict) else None
    if not isinstance(path, str) or not path:
        bad.append(str(path))
        continue
    target = os.path.normpath(os.path.join(rt, path))
    if target != rt and not target.startswith(rt + os.sep):
        bad.append(path)                                    # climbs out of the tree
    elif not os.path.exists(target):
        bad.append(path)
for path in bad:
    print(path)
sys.exit(5 if bad else 0)
PYEOF
}

check_manifest() {
    if ! have python3; then
        skip "manifest (missing python3)"
        return
    fi
    if [ ! -f "$MANIFEST" ] || [ ! -r "$MANIFEST" ]; then
        if [ "$ROUTE" = plugin ]; then
            fail "MANIFEST MISSING: $MANIFEST"
        else
            warnx "manifest absent (manual route): $MANIFEST"
        fi
        return
    fi

    local out rc line
    out="$(read_manifest "$MANIFEST" "$ROOT" 2>&1)"; rc=$?
    case "$rc" in
        0)  ok "manifest $MANIFEST" ;;
        5)  while IFS= read -r line; do
                [ -n "$line" ] || continue
                fail "DANGLING REF: $line"
            done <<<"$out"
            ;;
        *)  fail "MANIFEST MISSING: $MANIFEST ($out)" ;;
    esac
}

# ---------------------------------------------------------------------------
# Arm 5 — PLANS_ROOT, resolved through the ONE authority. Warning-only.
# ---------------------------------------------------------------------------
check_plans_root() {
    local helper="$ROOT/hooks/goalforge-plans-root.sh"
    if [ ! -f "$helper" ]; then
        warn "plans-root (resolution helper not found at $helper)"
        return
    fi
    if ! have git; then
        skip "plans-root (missing git)"
        return
    fi
    # shellcheck source=/dev/null
    . "$helper" || { warn "plans-root (helper could not be sourced)"; return; }
    if ! command -v goalforge_plans_roots >/dev/null 2>&1; then
        warn "plans-root (helper defines no goalforge_plans_roots)"
        return
    fi

    # The helper emits the <git-root>/plans leg ONLY for a non-empty file
    # argument; a bare call silently drops it and reports the global root.
    local first="" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ -n "$first" ] || first="$line"
    done < <(goalforge_plans_roots "$PWD/.")

    if [ -z "$first" ]; then
        warn "plans-root (no candidate resolved)"
        return
    fi
    local leg
    if [ -n "${SDD_PLANS_DIR:-}" ] && [ "$first" = "$SDD_PLANS_DIR" ]; then
        leg="leg 1: SDD_PLANS_DIR"
    elif [ -n "${HOME:-}" ] && [ "$first" = "$HOME/.claude/plans" ]; then
        leg="leg 3: global plans root"
    else
        leg="leg 2: git-root plans"
    fi
    ok "PLANS_ROOT: $first ($leg)"
}

# ---------------------------------------------------------------------------
# Arm 6 — git pre-commit validator. Meaningful only inside a work tree.
# ---------------------------------------------------------------------------
check_git_hook() {
    if ! have git; then
        skip "git-hook (missing git)"
        return
    fi
    if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        skip "git-hook (root not a git work tree)"
        return
    fi
    local gitdir hook line
    gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir=""
    if [ -z "$gitdir" ]; then
        skip "git-hook (root not a git work tree)"
        return
    fi
    hook="$gitdir/hooks/pre-commit"
    if [ ! -f "$hook" ]; then
        warn "git-hook (no pre-commit hook at $hook)"
        return
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *'>>> sdd-pre-commit >>>'*) ok "git-hook $hook"; return ;;
        esac
    done < "$hook"
    warn "git-hook (pre-commit hook at $hook carries no goalforge block)"
}

# ---------------------------------------------------------------------------
# Self-test — authored by task-02.
# ---------------------------------------------------------------------------
self_test() {
    printf 'goalforge-doctor: --self-test suite is not authored yet\n' >&2
    return 2
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
run_checks() {
    ROOT="${GF_DOCTOR_ROOT:-$SCRIPT_DIR/..}"
    ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || ROOT="${GF_DOCTOR_ROOT:-$SCRIPT_DIR/..}"
    MANIFEST="${GF_DOCTOR_MANIFEST:-$ROOT/references/reference-manifest.json}"
    ROUTE=manual

    check_deps
    check_bash_version
    if check_layout; then
        detect_route
        check_manifest
        check_plans_root
        check_git_hook
    else
        skip "route+manifest (bad root)"
        skip "plans-root (bad root)"
        skip "git-hook (bad root)"
    fi

    local promoted=0
    if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then
        promoted="$WARNINGS"
    fi
    printf 'goalforge-doctor: %d failure(s), %d warning(s), %d exempt warning(s)%s\n' \
        "$FAILURES" "$WARNINGS" "$EXEMPT" \
        "$( [ "$promoted" -gt 0 ] && printf ' — --strict promotes %d warning(s)' "$promoted" )"

    if [ "$FAILURES" -gt 0 ] || [ "$promoted" -gt 0 ]; then
        return 1
    fi
    return 0
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --strict)    STRICT=1; shift ;;
            --self-test) self_test; exit $? ;;
            -h|--help)   usage; exit 0 ;;
            *)           printf 'goalforge-doctor: unknown argument: %s\n' "$1" >&2
                         usage >&2
                         exit 2 ;;
        esac
    done
    run_checks
    exit $?
}

main "$@"
