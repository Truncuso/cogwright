#!/usr/bin/env bash
# goalforge-session-start.sh — SessionStart orientation block, owned by the
# goalforge plugin.
#
# One compact block answering "where did I leave off": active features with
# their frontier WP, handoffs sitting at `status: ready`, the wayfind open /
# frontier counts, and one routing line. Replaces the dotfiles-side
# wayfind/handoff SessionStart lines — the plugin that owns the chain owns the
# orientation for it, so installing or removing the plugin takes the injection
# with it.
#
# Contract:
#   plans root   resolved by the sourced goalforge-plans-root.sh — the ONE
#                resolution (SDD_PLANS_DIR, then <git-root>/plans, then
#                $HOME/.claude/plans). Never re-implemented here.
#   handoffs     $GOALFORGE_HANDOFFS_DIR, default <cwd git root>/docs/handoffs.
#                "ready" is a `status: ready` frontmatter key on a handoff .md,
#                the same predicate the handoff tooling lists on.
#   wayfind      <plans root>/<effort>/wayfind/ticket-*.md. The frontier count
#                comes from wayfind-frontier.sh when it resolves beside this
#                package; otherwise only the open count is printed (degrade,
#                never block).
#   routing      ONE constant line. Its wording belongs to the stage-report
#                template owner, not to this hook; nothing asserts the text.
#   size         at most 15 lines, hard-capped on the way out.
#   privacy      $HOME is rewritten to `~` and any e-mail address is redacted
#                before printing. This block lands in a transcript.
#   kill switch  GOALFORGE_SESSION_START=0 ⇒ print nothing, exit 0.
#
# Empty or unresolvable plans root ⇒ prints NOTHING (an empty banner is noise).
# ZERO-BREAKAGE: always exits 0.
#
# Usage:
#   <SessionStart JSON on stdin> | goalforge-session-start.sh
#   goalforge-session-start.sh --self-test
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
# shellcheck source=./goalforge-plans-root.sh
. "$HOOK_DIR/goalforge-plans-root.sh" 2>/dev/null || exit 0

MAX_LINES=15
MAX_FEATURES=8

# Print the first frontmatter value of key $2 in file $1, or nothing.
fm_value() {
    [ -f "$1" ] || return 0
    sed -n "s/^$2:[[:space:]]*[\"']\\{0,1\\}\\([^\"']*\\)[\"']\\{0,1\\}[[:space:]]*$/\\1/p" "$1" 2>/dev/null | head -n 1
}

# Print the first existing resolved plans root, or nothing.
#
# An explicitly-set SDD_PLANS_DIR is AUTHORITATIVE: when it names something
# that is not a directory this function prints nothing and the hook falls
# silent. It must never fall through to the git-root or $HOME candidate — a
# harness (or a user) that points the hook at a root which does not exist
# would otherwise get a block built from the live plans tree it was trying to
# stay out of (verify round 1, V1).
resolve_root() {
    local root
    if [ -n "${SDD_PLANS_DIR:-}" ]; then
        [ -d "$SDD_PLANS_DIR" ] && printf '%s' "$SDD_PLANS_DIR"
        return 0
    fi
    while IFS= read -r root; do
        [ -n "$root" ] && [ -d "$root" ] && { printf '%s' "$root"; return 0; }
    done < <(goalforge_plans_roots "$PWD/plans/.")
    return 0
}

# "<wp-basename> [<status>]" for the frontier WP of feature dir $1, or the
# feature's own status when it holds no WP directories. The frontier WP is the
# first `ready` one; failing that the first one not yet verified/archived.
frontier_wp() {
    local feat="$1" d st fallback=""
    for d in "$feat"/*/; do
        [ -f "$d/overview.md" ] || continue
        st="$(fm_value "$d/overview.md" status)"
        [ -n "$st" ] || st="?"
        if [ "$st" = "ready" ]; then
            printf '%s [%s]' "$(basename "$d")" "$st"
            return 0
        fi
        case "$st" in
            verified|archived|abandoned) ;;
            *) [ -n "$fallback" ] || fallback="$(basename "$d") [$st]" ;;
        esac
    done
    if [ -n "$fallback" ]; then printf '%s' "$fallback"; return 0; fi
    st="$(fm_value "$feat/overview.md" status)"
    [ -n "$st" ] && printf 'no open WP [feature: %s]' "$st"
    return 0
}

# Feature lines for plans root $1.
feature_lines() {
    local root="$1" feat base line n=0
    for feat in "$root"/*/; do
        [ -d "$feat" ] || continue
        base="$(basename "$feat")"
        case "$base" in _*|.*) continue ;; esac
        # The header says ACTIVE features: a finished one must not occupy one
        # of the MAX_FEATURES slots and evict an active feature later in the
        # alphabet (verify round 1, V4).
        case "$(fm_value "$feat/overview.md" status)" in
            completed|archived) continue ;;
        esac
        line="$(frontier_wp "$feat")"
        [ -n "$line" ] || continue
        printf '  %s: %s\n' "$base" "$line"
        n=$((n + 1))
        [ "$n" -ge "$MAX_FEATURES" ] && break
    done
}

# Space-separated slugs of handoffs at `status: ready` under $1.
ready_handoffs() {
    local dir="$1" f slug out=""
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    for f in "$dir"/*/*.md; do
        [ -f "$f" ] || continue
        case "$f" in */_archived/*) continue ;; esac
        [ "$(fm_value "$f" status)" = "ready" ] || continue
        slug="$(basename "$(dirname "$f")")"
        case " $out " in *" $slug "*) continue ;; esac
        out="$out $slug"
    done
    printf '%s' "${out# }"
}

# "<open> open, <frontier> on the frontier" (or just the open count).
wayfind_counts() {
    local root="$1" eff open=0 front="" total_front=0 have_front=0 script out
    script="$HOOK_DIR/../wayfind/scripts/wayfind-frontier.sh"
    [ -f "$script" ] || script="$HOOK_DIR/../skills/wayfind/scripts/wayfind-frontier.sh"
    for eff in "$root"/*/; do
        [ -d "$eff/wayfind" ] || continue
        open=$((open + $(grep -l '^status:[[:space:]]*open' "$eff"/wayfind/ticket-*.md 2>/dev/null | wc -l)))
        if [ -f "$script" ]; then
            out="$(bash "$script" "$eff" 2>/dev/null)" || out=""
            front="$(printf '%s' "$out" | tr ',' '\n' | grep -c '"ticket-' 2>/dev/null)" || front=0
            case "$front" in ''|*[!0-9]*) front=0 ;; esac
            total_front=$((total_front + front)); have_front=1
        fi
    done
    [ "$open" -eq 0 ] && [ "$total_front" -eq 0 ] && return 0
    if [ "$have_front" -eq 1 ]; then
        printf '%s open, %s on the frontier' "$open" "$total_front"
    else
        printf '%s open' "$open"
    fi
}

# stdin -> stdout, privacy-scrubbed and capped. The block lands in a
# transcript, so it carries no absolute home path and no e-mail address.
emit() {
    local home="${HOME:-/nonexistent-home}"
    sed -e "s#${home%/}#~#g" \
        -e 's#[A-Za-z0-9._%+-][A-Za-z0-9._%+-]*@[A-Za-z0-9.-][A-Za-z0-9.-]*\.[A-Za-z][A-Za-z]*#<redacted>#g' \
        | head -n "$MAX_LINES"
}

build_block() {
    local root="$1" feats handoffs way
    feats="$(feature_lines "$root")"
    [ -n "$feats" ] || return 0
    echo "goalforge orientation"
    printf '%s\n' "$feats"
    handoffs="$(ready_handoffs "${GOALFORGE_HANDOFFS_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)/docs/handoffs}")"
    [ -n "$handoffs" ] && echo "  handoffs ready: $handoffs"
    way="$(wayfind_counts "$root")"
    [ -n "$way" ] && echo "  wayfind: $way"
    echo "  route: /spec -> /plan -> /implement -> /verify (goalforge-run drives the whole chain)"
    return 0
}

self_test() {
    local p=0 f=0 d out
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }
    echo "=== goalforge-session-start.sh --self-test ==="
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' RETURN

    mkdir -p "$d/plans/feat-a/wp-01" "$d/plans/feat-a/wp-02" "$d/empty"
    printf -- '---\nstatus: verified\n---\n' > "$d/plans/feat-a/wp-01/overview.md"
    printf -- '---\nstatus: ready\n---\n'    > "$d/plans/feat-a/wp-02/overview.md"
    printf -- '---\nstatus: active\n---\n'   > "$d/plans/feat-a/overview.md"

    out="$(SDD_PLANS_DIR="$d/plans" bash "$SELF" </dev/null 2>&1)"
    case "$out" in *"feat-a: wp-02 [ready]"*) ok "frontier WP is the ready one" ;;
        *) no "frontier WP line missing: '$out'" ;; esac
    [ "$(printf '%s\n' "$out" | wc -l)" -le "$MAX_LINES" ] \
        && ok "block is <= $MAX_LINES lines" || no "block exceeded $MAX_LINES lines"

    out="$(SDD_PLANS_DIR="$d/empty" bash "$SELF" </dev/null 2>&1)"
    [ -z "$out" ] && ok "empty plans root -> prints nothing" || no "empty root printed '$out'"

    out="$(SDD_PLANS_DIR="$d/plans" GOALFORGE_SESSION_START=0 bash "$SELF" </dev/null 2>&1)"
    [ -z "$out" ] && ok "GOALFORGE_SESSION_START=0 -> silent" || no "kill switch printed '$out'"

    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

[ "${GOALFORGE_SESSION_START:-1}" = "0" ] && exit 0
cat >/dev/null 2>&1 || true      # drain the SessionStart payload; unused

ROOT="$(resolve_root)"
[ -n "${ROOT:-}" ] || exit 0
build_block "$ROOT" 2>/dev/null | emit
exit 0
