#!/usr/bin/env bash
# goalforge-expertise-map.test.sh — wp-02 T2 / behavior b2.
#
# Admission contract for references/expertise-map.yaml: every bundle value
# is a CORPUS-RELATIVE path under a corpus root that resolves to an existing
# file or skill directory. An `agents/<name>.md` PATH is admissible (read as
# knowledge, never dispatched — wp-02 OQ1); a bare specialist NAME such as
# `typescript-pro` is not.
#
# Lanes, and why they are split:
#
#   SHAPE (deterministic, no root)   the live map — every value has a `/`,
#                                    is relative, and sits under an
#                                    admissible prefix. Machine-independent.
#   RESOLUTION (deterministic)       runs against the SHIPPED hermetic
#                                    corpus at evals/fixtures/expertise-map/
#                                    corpus/: good.yaml resolves (exit 0),
#                                    missing-path.yaml does not (exit 2).
#   RESOLUTION (WARN, live root)     the live map against
#                                    ${CLAUDE_CONFIG_DIR:-$HOME/.claude}.
#                                    Lists what does not resolve on THIS
#                                    machine and never fails: the live corpus
#                                    is sibling-owned data this repo does not
#                                    ship (rules/common/testing.md, pinned
#                                    sibling-owned-data anti-pattern).
#
#   `--check <map> [--root <dir>]` is the validator. With no --root the
#   resolution half is skipped and only shape is decided.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
MAP="$PKG/references/expertise-map.yaml"
FIXTURES="$PKG/evals/fixtures/expertise-map"
CORPUS="$FIXTURES/corpus"
LIVE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ── validator ────────────────────────────────────────────────────────────
# Extracts every flow-list value and checks shape, then — only when a root
# is given — resolution under that root.
check_map() {
    local f="$1" root="${2:-}" bad=0
    if [[ ! -f "$f" ]]; then
        echo "    no such map: $f"
        return 2
    fi

    local values
    values="$(grep -oE '\[[^]]*\]' "$f" \
              | tr -d '[]' | tr ',' '\n' \
              | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
              | grep -v '^$' || true)"
    if [[ -z "$values" ]]; then
        echo "    no bundle values found (expected flow-style lists)"
        return 2
    fi

    while IFS= read -r v; do
        # shape: a bare specialist NAME has no path separator.
        if [[ "$v" != */* ]]; then
            echo "    bare specialist name is inadmissible: $v"
            bad=1
            continue
        fi
        case "$v" in
            /*|*..*|'~'*)
                echo "    value must be corpus-relative under the corpus root: $v"
                bad=1
                continue
                ;;
        esac
        case "$v" in
            rules/*|agents/*|skills/*) ;;
            *) echo "    value outside rules/ agents/ skills/: $v"; bad=1; continue ;;
        esac
        # resolution: only when a root was supplied.
        if [[ -n "$root" ]] && [[ ! -e "$root/$v" ]]; then
            echo "    does not resolve under the corpus root: $v"
            bad=1
        fi
    done <<<"$values"

    [[ "$bad" -eq 0 ]] && return 0 || return 2
}

if [[ "${1:-}" == "--check" ]]; then
    CHECK_FILE="${2:?--check needs a file}"
    CHECK_ROOT=""
    if [[ "${3:-}" == "--root" ]]; then
        CHECK_ROOT="${4:?--root needs a directory}"
    fi
    check_map "$CHECK_FILE" "$CHECK_ROOT"
    exit $?
fi

# ── harness ──────────────────────────────────────────────────────────────
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SELF="${BASH_SOURCE[0]}"

# the hermetic corpus must be checked in, or the resolution lane is vacuous.
if [[ -d "$CORPUS" ]]; then
    ok "shipped fixture corpus present at evals/fixtures/expertise-map/corpus/"
else
    bad "shipped fixture corpus present at evals/fixtures/expertise-map/corpus/ (missing: $CORPUS)"
fi

# shape: the three documented key groups exist.
KEYS_OK=1
for k in by_extension by_tag by_task_type; do
    grep -qE "^$k:" "$MAP" || { KEYS_OK=0; echo "    missing key group: $k"; }
done
if [[ "$KEYS_OK" -eq 1 ]]; then
    ok "expertise-map.yaml has by_extension / by_tag / by_task_type"
else
    bad "expertise-map.yaml has by_extension / by_tag / by_task_type"
fi

# SHAPE lane — the live map, no root. Machine-independent.
OUT="$(bash "$SELF" --check "$MAP" 2>&1)"; RC=$?
if [[ "$RC" -eq 0 ]]; then
    ok "live expertise-map.yaml: every value well-shaped and corpus-relative (exit 0)"
else
    bad "live expertise-map.yaml: shape exit 0 (rc=$RC)${OUT:+ — $OUT}"
fi

# RESOLUTION lane, deterministic — known-good map against the shipped corpus.
OUT="$(bash "$SELF" --check "$FIXTURES/good.yaml" --root "$CORPUS" 2>&1)"; RC=$?
if [[ "$RC" -eq 0 ]]; then
    ok "known-good good.yaml resolves under the shipped corpus (exit 0)"
else
    bad "known-good good.yaml resolves under the shipped corpus (rc=$RC)${OUT:+ — $OUT}"
fi

# an agents/<name>.md PATH is admissible as expertise (OQ1) — assert the
# map actually exercises that shape, or the rule is untested.
if grep -qE '\bagents/[a-z0-9-]+\.md\b' "$MAP"; then
    ok "map carries at least one agents/<name>.md path (OQ1 shape exercised)"
else
    bad "map carries at least one agents/<name>.md path (OQ1 shape exercised)"
fi

# specialist-map.yaml is wp-03's to retire — untouched here, but it must
# still exist, or this WP silently took over its retirement.
if [[ -f "$PKG/references/specialist-map.yaml" ]]; then
    ok "references/specialist-map.yaml left in place (wp-03 retires it)"
else
    bad "references/specialist-map.yaml left in place (wp-03 retires it)"
fi

# known-bad ---------------------------------------------------------------
# Each fixture must exist AND be rejected for its OWN defect: a missing
# fixture also exits 2 ("no such map"), so exit 2 alone is a check that
# cannot fail. bare-name is a shape defect (no root needed); missing-path is
# a resolution defect, decided against the SHIPPED corpus.
for fx in bare-name missing-path; do
    f="$FIXTURES/$fx.yaml"
    if [[ ! -f "$f" ]]; then
        bad "known-bad $fx.yaml: fixture missing at $f"
        continue
    fi
    case "$fx" in
        bare-name)    WANT='bare specialist name is inadmissible:'; ARGS=() ;;
        missing-path) WANT='does not resolve under the corpus root:'; ARGS=(--root "$CORPUS") ;;
    esac
    OUT="$(bash "$SELF" --check "$f" "${ARGS[@]+"${ARGS[@]}"}" 2>&1)"; RC=$?
    FIRST="$(head -1 <<<"$OUT" | sed 's/^ *//')"
    if [[ "$RC" -ne 2 ]]; then
        bad "known-bad $fx.yaml: expected exit 2, got $RC${OUT:+ — $OUT}"
    elif ! grep -qE "$WANT" <<<"$FIRST"; then
        bad "known-bad $fx.yaml: exit 2 for the wrong reason — want /$WANT/, got: $FIRST"
    else
        ok "known-bad $fx.yaml: exit 2 ($FIRST)"
    fi
done

# WARN lane — the live map against the live corpus root. Advisory only: the
# corpus is sibling-owned data this repo does not ship, so an unresolved
# value is reported, never failed.
if [[ ! -d "$LIVE_ROOT" ]]; then
    echo "  WARN: live corpus root absent ($LIVE_ROOT) — live resolution not checked"
else
    LIVE_OUT="$(bash "$SELF" --check "$MAP" --root "$LIVE_ROOT" 2>&1)"
    UNRES="$(grep -F 'does not resolve under the corpus root:' <<<"$LIVE_OUT" \
             | sed 's/^ *//' | sort -u || true)"
    if [[ -z "$UNRES" ]]; then
        echo "  INFO: every live map value resolves under $LIVE_ROOT"
    else
        echo "  WARN: $(grep -c . <<<"$UNRES") map value(s) do not resolve under $LIVE_ROOT (advisory, not a failure):"
        sed 's/^/    WARN: /' <<<"$UNRES"
    fi
fi

echo
echo "goalforge-expertise-map.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
