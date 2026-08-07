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
# Self-test — 11 hermetic offline cases proving each arm actually fires.
#
# Every case runs the doctor against a SYNTHETIC root with PATH narrowed to a
# shim dir, so the suite never consults the host's PATH, its site-packages, or a
# real plans/ directory, and nothing under plugins/ or packages/ is ever
# written. Each case asserts the arm's stable token AND the exit code: an exit 1
# from a `set -u` abort is otherwise indistinguishable from the arm firing.
#
# Every negative case is the positive control's fixture with exactly ONE thing
# broken, so a failure is attributable to the injection rather than to the
# sandbox.
# ---------------------------------------------------------------------------
self_test() {
    local real_python3 real_bash real_dirname sandbox
    real_python3="$(command -v python3)" || real_python3=""
    real_dirname="$(command -v dirname)" || real_dirname=""
    real_bash="${BASH:-}"
    [ -n "$real_bash" ] || real_bash="$(command -v bash)"
    if [ -z "$real_python3" ] || [ -z "$real_dirname" ] || [ -z "$real_bash" ]; then
        printf 'self-test: need python3, dirname and bash on PATH to build the fixtures\n' >&2
        return 2
    fi

    sandbox="$(mktemp -d)" || return 2
    # shellcheck disable=SC2064  # $sandbox must expand now, not at trap time
    trap "rm -rf '$sandbox'" EXIT

    local helper_src="$SCRIPT_DIR/../hooks/goalforge-plans-root.sh"
    if [ ! -f "$helper_src" ]; then
        printf 'self-test: resolution helper not found at %s\n' "$helper_src" >&2
        return 2
    fi

    # --- fixture builders -------------------------------------------------
    # make_root <dir> <plugin|manual> [--no-manifest]
    make_root() {
        local d="$1" flavour="$2" manifest="${3:-}"
        mkdir -p "$d/scripts" "$d/hooks" "$d/references" || return 1
        printf -- '---\nname: fixture\n---\n' > "$d/SKILL.md"
        printf '# fixture\n' > "$d/references/schema.md"
        printf '#!/bin/sh\nexit 0\n' > "$d/scripts/fixture.sh"
        cp "$helper_src" "$d/hooks/goalforge-plans-root.sh" || return 1
        [ "$flavour" = plugin ] && {
            mkdir -p "$d/.claude-plugin"
            printf '{ "name": "goalforge" }\n' > "$d/.claude-plugin/plugin.json"
        }
        [ "$manifest" = --no-manifest ] || write_manifest \
            "$d/references/reference-manifest.json" \
            'references/schema.md' 'scripts/fixture.sh'
        return 0
    }

    # write_manifest <file> <path>... — schema-1 manifest naming the given refs.
    write_manifest() {
        local f="$1" p
        shift
        {
            printf '{\n  "schema": 1,\n  "refs": [\n'
            local sep=""
            for p in "$@"; do
                printf '%s    { "from": "SKILL.md", "path": "%s" }' "$sep" "$p"
                sep=$',\n'
            done
            printf '\n  ]\n}\n'
        } > "$f"
    }

    # make_shim <dir> [--without <cmd>]... [--no-pyyaml]
    #
    # Stubs the SEVEN probed deps only. `bash`, `sh` and `env` are NEVER stubbed
    # (they run the suite, the stubs, and the doctor's shebang), and `dirname` is
    # SYMLINKED to the real binary rather than stubbed — the sourced plans-root
    # helper needs a working one. Stubbing any of them would break the harness
    # instead of the arm under test.
    make_shim() {
        local d="$1"; shift
        local -a without=()
        local no_pyyaml=0 arg c
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --without)   without+=("$2"); shift 2 ;;
                --no-pyyaml) no_pyyaml=1; shift ;;
                *)           shift ;;
            esac
        done
        mkdir -p "$d" || return 1
        for c in "${DEPS[@]}"; do
            local skipthis=0
            for arg in ${without+"${without[@]}"}; do
                [ "$arg" = "$c" ] && skipthis=1
            done
            [ "$skipthis" -eq 1 ] && continue
            case "$c" in
                python3)
                    # -S keeps the host's site-packages out, so the PyYAML arm is
                    # decided by the fixture stub alone. The interpreter path is
                    # ABSOLUTE and captured before PATH narrowing: a bare
                    # `exec python3` would re-resolve to this stub and recurse.
                    if [ "$no_pyyaml" -eq 1 ]; then
                        printf '#!/bin/sh\nexec %s -S -E "$@"\n' "$real_python3" > "$d/python3"
                    else
                        printf '#!/bin/sh\nPYTHONPATH=%s exec %s -S "$@"\n' \
                            "$sandbox/pylib" "$real_python3" > "$d/python3"
                    fi
                    ;;
                git)
                    # --show-toplevel answers only when the case asks for it, so
                    # the PLANS_ROOT leg-2 case needs no real repository; every
                    # other fixture is reported as NOT a work tree, which makes
                    # the git-hook arm SKIPPED (neither warning nor failure).
                    printf '%s\n' \
                        '#!/bin/sh' \
                        'for a in "$@"; do' \
                        '  case "$a" in' \
                        '    --show-toplevel)' \
                        '      [ -n "${GF_TEST_TOPLEVEL:-}" ] || exit 1' \
                        '      echo "$GF_TEST_TOPLEVEL"; exit 0 ;;' \
                        '    --is-inside-work-tree|--absolute-git-dir) exit 1 ;;' \
                        '  esac' \
                        'done' \
                        'exit 1' > "$d/git"
                    ;;
                *)
                    printf '#!/bin/sh\nexit 0\n' > "$d/$c"
                    ;;
            esac
            chmod +x "$d/$c"
        done
        ln -sf "$real_dirname" "$d/dirname"
        return 0
    }

    # --- case runner ------------------------------------------------------
    local n=0 pass=0 fail=0

    # run_case <name> <want_exit> <must_have> <must_not_have;…> <cmd>...
    run_case() {
        local name="$1" want="$2" have="$3" absent="$4"
        shift 4
        n=$(( n + 1 ))
        local out rc why="" tok line
        out="$("$@" 2>&1)"; rc=$?
        [ "$rc" -eq "$want" ] || why="exit $rc, want $want"
        if [ -n "$have" ]; then
            case "$out" in
                *"$have"*) ;;
                *) why="${why:+$why; }missing token '$have'" ;;
            esac
        fi
        if [ -n "$absent" ]; then
            local IFS=';'
            for tok in $absent; do
                [ -n "$tok" ] || continue
                case "$out" in
                    *"$tok"*) why="${why:+$why; }unexpected token '$tok'" ;;
                esac
            done
        fi
        if [ -n "$why" ]; then
            fail=$(( fail + 1 ))
            printf 'case %d/11: %s FAIL (%s)\n' "$n" "$name" "$why"
            while IFS= read -r line; do printf '    | %s\n' "$line"; done <<<"$out"
        else
            pass=$(( pass + 1 ))
            printf 'case %d/11: %s PASS\n' "$n" "$name"
        fi
    }

    # --- fixtures ---------------------------------------------------------
    mkdir -p "$sandbox/pylib"
    : > "$sandbox/pylib/yaml.py"

    local r_plugin="$sandbox/root-plugin"
    local r_manual="$sandbox/root-manual"
    local r_nomani="$sandbox/root-plugin-nomanifest"
    local r_bad="$sandbox/root-bad"
    local leg2="$sandbox/leg2-repo"
    make_root "$r_plugin" plugin      || return 2
    make_root "$r_manual" manual --no-manifest || return 2
    make_root "$r_nomani" plugin --no-manifest || return 2
    mkdir -p "$r_bad" "$leg2"         || return 2
    write_manifest "$sandbox/dangling-manifest.json" \
        'references/schema.md' 'references/does-not-exist.md'

    local shim_full="$sandbox/shim-full"
    local shim_nojq="$sandbox/shim-nojq"
    local shim_noflock="$sandbox/shim-noflock"
    local shim_noyaml="$sandbox/shim-noyaml"
    make_shim "$shim_full"                        || return 2
    make_shim "$shim_nojq"    --without jq        || return 2
    make_shim "$shim_noflock" --without flock     || return 2
    make_shim "$shim_noyaml"  --no-pyyaml         || return 2

    # A clean environment for every child run: no seam and no plans-root
    # override may leak in from the shell that invoked --self-test.
    local -a base=(env -u SDD_PLANS_DIR -u GF_DOCTOR_MANIFEST
                   -u GF_DOCTOR_BASH_VERSINFO -u GF_TEST_TOPLEVEL
                   -u CLAUDE_PLUGIN_ROOT -u PYTHONPATH)
    local hard='MISSING DEP:;DANGLING REF:;MANIFEST MISSING;BAD ROOT:'

    # Case 8 runs the doctor twice: bare, then --strict. The exemption means
    # BOTH must exit 0, so a promoted manifest warning surfaces as exit 3.
    case_manual_manifest() {
        local rc1 rc2
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_manual" \
            "$real_bash" "$SELF"; rc1=$?
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_manual" \
            "$real_bash" "$SELF" --strict; rc2=$?
        [ "$rc2" -eq 0 ] || return 3
        return "$rc1"
    }

    # Case 9 needs the cwd inside the fixture repo: the helper anchors the
    # git-root leg on the file argument's directory.
    case_plans_root_leg2() {
        cd "$leg2" || return 2
        "${base[@]}" PATH="$shim_full" GF_TEST_TOPLEVEL="$leg2" \
            GF_DOCTOR_ROOT="$r_plugin" "$real_bash" "$SELF"
    }

    printf '=== goalforge doctor self-test (11 cases) ===\n'

    run_case positive-control 0 'ok   route plugin' "$hard" \
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_plugin" \
        "$real_bash" "$SELF"

    run_case missing-jq 1 'MISSING DEP: jq' '' \
        "${base[@]}" PATH="$shim_nojq" GF_DOCTOR_ROOT="$r_plugin" \
        "$real_bash" "$SELF"

    run_case missing-flock 1 'MISSING DEP: flock' '' \
        "${base[@]}" PATH="$shim_noflock" GF_DOCTOR_ROOT="$r_plugin" \
        "$real_bash" "$SELF"

    run_case bash-3.2-bare 0 'WARN: bash<4' "$hard" \
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_plugin" \
        GF_DOCTOR_BASH_VERSINFO=3 "$real_bash" "$SELF"

    run_case bash-3.2-strict 1 'WARN: bash<4' "$hard" \
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_plugin" \
        GF_DOCTOR_BASH_VERSINFO=3 "$real_bash" "$SELF" --strict

    run_case dangling-ref 1 'DANGLING REF: references/does-not-exist.md' '' \
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_plugin" \
        GF_DOCTOR_MANIFEST="$sandbox/dangling-manifest.json" \
        "$real_bash" "$SELF"

    run_case plugin-route-manifest-missing 1 'MANIFEST MISSING' '' \
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_nomani" \
        "$real_bash" "$SELF"

    run_case manual-route-manifest-absent 0 'WARN: manifest' "$hard" \
        case_manual_manifest

    run_case plans-root-leg2 0 "PLANS_ROOT: $leg2/plans (leg 2" "$hard" \
        case_plans_root_leg2

    run_case bad-root 1 "BAD ROOT: $r_bad" 'PLANS_ROOT:' \
        "${base[@]}" PATH="$shim_full" GF_DOCTOR_ROOT="$r_bad" \
        "$real_bash" "$SELF"

    run_case pyyaml-missing 1 'MISSING DEP: PyYAML' '' \
        "${base[@]}" PATH="$shim_noyaml" GF_DOCTOR_ROOT="$r_plugin" \
        "$real_bash" "$SELF"

    printf '=== self-test: %d passed, %d failed ===\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
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
