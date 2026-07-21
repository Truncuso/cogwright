#!/usr/bin/env bash
# goalforge-preharden-lint.sh — deterministic pre-harden lint for one WP dir.
#
# Catches, BEFORE a harden panel spends tokens on them, the two defect classes
# the goalforge harden panels repeatedly re-found across old WPs
# (improvement-report process note, 2026-07-19):
#
#   P1  plugin-anchored paths in planning docs ($COGWRIGHT_ROOT,
#       $CLAUDE_PLUGIN_ROOT, plugins/cogwright literals) — the local tree is
#       authoritative (wp-13), plugin paths are stale anchors.
#   V1  `|| true` no-op inside a task verify: block — the check can never fail.
#   V2  self-referential verify — the verify: block greps/reads only the WP's
#       own planning docs (overview.md / task-*.md / findings.md), proving the
#       words exist, not the work.
#   V3  no executable check — verify: block contains only echo/printf/comments.
#   V4  sole `--help` probe — the only command is a `--help` invocation.
#
# Usage: goalforge-preharden-lint.sh <wp-dir> | --self-test
# Exit: 0 clean; 1 findings (WARN lines on stdout, gate-consumable); 2 usage.
# Offline, deterministic, no LLM. sdd-* diagnostic prefix per CLI-surface freeze.
set -uo pipefail

warn_count=0
warn() { echo "WARN [$1] $2"; warn_count=$((warn_count+1)); }

# Print the verify: block scalar body of a task file (indented lines after
# `verify: |`), stripped of the two-space indent.
verify_block() {
    awk '
        /^verify: \|/ { grab=1; next }
        grab && /^[a-z_]+:/ { grab=0 }
        grab && /^---$/ { grab=0 }
        grab { sub(/^  /, ""); print }
    ' "$1"
}

lint_wp() {
    local wp="$1" f base vb
    [ -d "$wp" ] || { echo "sdd-preharden-lint: not a directory: $wp" >&2; return 2; }

    # P1 — plugin-anchored paths anywhere in the WP's planning docs
    local m
    for f in "$wp"/overview.md "$wp"/task-*.md; do
        [ -f "$f" ] || continue
        base="$(basename -- "$f")"
        m="$(grep -oE '\$COGWRIGHT_ROOT|\$CLAUDE_PLUGIN_ROOT|plugins/cogwright' "$f" 2>/dev/null | head -1)"
        if [ -n "$m" ]; then
            warn P1 "$base: plugin-anchored path ($m) — local tree is authoritative"
        fi
    done

    # V1–V4 — per task verify: block
    for f in "$wp"/task-*.md; do
        [ -f "$f" ] || continue
        base="$(basename -- "$f")"
        vb="$(verify_block "$f")"
        [ -n "$vb" ] || continue

        if printf '%s' "$vb" | grep -q '|| true'; then
            warn V1 "$base: verify contains '|| true' — check can never fail"
        fi

        # commands = non-empty, non-comment lines
        local cmds echo_only
        cmds="$(printf '%s\n' "$vb" | grep -vE '^\s*(#|$)')"
        if [ -n "$cmds" ]; then
            # V2: every referenced path token that exists points inside the WP's own docs
            if printf '%s\n' "$cmds" | grep -qE '(grep|cat|test -f|\[ -f)' \
               && ! printf '%s\n' "$cmds" | grep -vE '(overview\.md|task-[a-z0-9-]*\.md|findings\.md|todo\.md)' | grep -qE '(grep|cat|test -f|\[ -f|bash|python3|pytest|sh )'; then
                warn V2 "$base: verify only inspects the WP's own planning docs (self-referential)"
            fi
            # V3: only echo/printf lines
            echo_only=1
            while IFS= read -r line; do
                printf '%s' "$line" | grep -qE '^\s*(echo|printf)\b' || { echo_only=0; break; }
            done <<EOF
$cmds
EOF
            [ "$echo_only" -eq 1 ] && warn V3 "$base: verify has no executable check (echo/printf only)"
            # V4: sole command is a --help probe
            if [ "$(printf '%s\n' "$cmds" | grep -c .)" -eq 1 ] && printf '%s' "$cmds" | grep -q -- '--help'; then
                warn V4 "$base: verify is a bare --help probe"
            fi
        fi
    done

    [ "$warn_count" -eq 0 ]
}

self_test() {
    local d p=0 f=0
    d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
    ok(){ echo "  PASS: $1"; p=$((p+1)); }
    no(){ echo "  FAIL: $1"; f=$((f+1)); }
    echo "=== sdd-preharden-lint: --self-test ==="

    # dirty fixture: trips P1, V1, V2, V3, V4
    mkdir -p "$d/dirty"
    printf -- '---\nname: wp-x\n---\npath $COGWRIGHT_ROOT/scripts\n' > "$d/dirty/overview.md"
    printf -- '---\nname: task-01-a\nverify: |\n  bash run.sh || true\n---\nbody\n' > "$d/dirty/task-01-a.md"
    printf -- '---\nname: task-02-b\nverify: |\n  grep -q Goal overview.md\n---\nbody\n' > "$d/dirty/task-02-b.md"
    printf -- '---\nname: task-03-c\nverify: |\n  echo done\n---\nbody\n' > "$d/dirty/task-03-c.md"
    printf -- '---\nname: task-04-d\nverify: |\n  mytool --help\n---\nbody\n' > "$d/dirty/task-04-d.md"
    local out rc
    out="$(warn_count=0; lint_wp "$d/dirty")"; rc=$?
    [ "$rc" -eq 1 ] && ok "dirty WP -> exit 1" || no "dirty WP -> exit $rc (want 1)"
    for tag in P1 V1 V2 V3 V4; do
        printf '%s' "$out" | grep -q "\[$tag\]" && ok "dirty WP trips $tag" || no "dirty WP misses $tag ($out)"
    done

    # clean fixture: real check, repo file, no anchors
    mkdir -p "$d/clean"
    printf -- '---\nname: wp-y\n---\nlocal paths only\n' > "$d/clean/overview.md"
    printf -- '---\nname: task-01-real\nverify: |\n  bash scripts/run-tests.sh\n  grep -q slug src/slugger.py\n---\nbody\n' > "$d/clean/task-01-real.md"
    out="$(warn_count=0; lint_wp "$d/clean")"; rc=$?
    [ "$rc" -eq 0 ] && ok "clean WP -> exit 0" || no "clean WP -> exit $rc (want 0): $out"

    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

case "${1:-}" in
    --self-test) self_test; exit $? ;;
    "") echo "usage: goalforge-preharden-lint.sh <wp-dir> | --self-test" >&2; exit 2 ;;
    *) lint_wp "$1"; exit $? ;;
esac
