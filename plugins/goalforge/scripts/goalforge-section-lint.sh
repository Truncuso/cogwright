#!/usr/bin/env bash
# goalforge-section-lint.sh — deterministic C1 section-shape lint for one WP
# overview.md.
#
# spec.md Interface Contract C1: a schema-6 WP overview carries EXACTLY the
# 8 fixed `## ` (H2) sections below, in this order, and no other H2:
#
#   Goal, Verification, Owned Files, Depends On, Checklist, Open Questions,
#   Decisions, Goal Changelog
#
# Usage: goalforge-section-lint.sh <overview.md>
# Exit 0: the H2 set equals the C1 set, in order.
# Exit 2: any other/missing/reordered H2, or an internal error (unreadable
#         file, no frontmatter) — fail-closed (ticket-74: an internal error
#         is never a silent pass).
# A one-line reason is printed to stderr on exit 2. Emits `gate.result`
# (gate=section-lint) via goalforge-trace-emit, best-effort — a rejected or
# unavailable emitter never changes this script's own exit code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The C1 shape, in order.
readonly -a C1_SECTIONS=(
    "Goal" "Verification" "Owned Files" "Depends On" "Checklist"
    "Open Questions" "Decisions" "Goal Changelog"
)

# Best-effort gate.result emit — never affects this script's exit code.
emit_gate_result() {
    local result="$1" reason="$2" wp="$3" feat_dir="$4" emit
    emit="$SCRIPT_DIR/goalforge-trace-emit"
    [ -x "$emit" ] || return 0
    [ -n "$feat_dir" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    WP="$wp" RESULT="$result" REASON="$reason" python3 -c '
import json, os, sys
sys.stdout.write(json.dumps({
    "type": "gate.result",
    "wp": os.environ["WP"],
    "gate": "section-lint",
    "result": os.environ["RESULT"],
    "reason": os.environ["REASON"],
}))
' 2>/dev/null | "$emit" --feature-dir "$feat_dir" >/dev/null 2>&1 || true
    return 0
}

# Prints one H2 heading text per line, in document order, from the BODY
# (after the closing frontmatter `---`). Prints nothing and returns 1 if the
# file has no frontmatter block (`--- ... ---` at the top).
h2_sections() {
    local f="$1"
    awk '
        NR==1 && $0=="---" { infm=1; next }
        infm && $0=="---" { infm=0; seenfm=1; next }
        infm { next }
        /^## / { sub(/^## /, ""); sub(/[ \t]+$/, ""); print; next }
    ' "$f"
}

has_frontmatter() {
    local f="$1" first
    first="$(head -n1 "$f" 2>/dev/null)"
    [ "$first" = "---" ]
}

wp_name() {
    # arg: overview.md path. Falls back to the WP dir basename.
    local f="$1" n
    n="$(awk 'NR==1 && $0=="---"{infm=1;next} infm && $0=="---"{exit} infm && /^name:[ \t]*/ {sub(/^name:[ \t]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f" 2>/dev/null)"
    [ -n "$n" ] && printf '%s' "$n" || basename "$(dirname "$f")"
}

lint() {
    local f="$1" wp feat_dir got_str want_str reason
    local -a got=()

    if [ ! -f "$f" ]; then
        echo "goalforge-section-lint: internal error — not a file: $f" >&2
        emit_gate_result "fail" "internal-error: not a file: $f" "$(basename "${f%.md}")" ""
        return 2
    fi
    if ! has_frontmatter "$f"; then
        echo "goalforge-section-lint: internal error — no frontmatter block in $f" >&2
        emit_gate_result "fail" "internal-error: no frontmatter" "$(basename "$(dirname "$f")")" "$(dirname "$(dirname "$f")")"
        return 2
    fi

    wp="$(wp_name "$f")"
    feat_dir="$(dirname "$(dirname "$f")")"

    while IFS= read -r line; do
        [ -n "$line" ] && got+=("$line")
    done < <(h2_sections "$f")

    got_str="$(printf '%s\n' "${got[@]:-}")"
    want_str="$(printf '%s\n' "${C1_SECTIONS[@]}")"

    if [ "$got_str" = "$want_str" ]; then
        emit_gate_result "pass" "8/8 C1 sections in order" "$wp" "$feat_dir"
        return 0
    fi

    # Build a specific reason: extra sections, missing sections, or reorder.
    local extra=() missing=() s found
    if [ "${#got[@]}" -gt 0 ]; then
        for s in "${got[@]}"; do
            found=0
            for w in "${C1_SECTIONS[@]}"; do [ "$s" = "$w" ] && { found=1; break; }; done
            [ "$found" -eq 0 ] && extra+=("$s")
        done
    fi
    for w in "${C1_SECTIONS[@]}"; do
        found=0
        for s in "${got[@]:-}"; do [ "$s" = "$w" ] && { found=1; break; }; done
        [ "$found" -eq 0 ] && missing+=("$w")
    done

    if [ "${#extra[@]}" -gt 0 ]; then
        reason="disallowed H2 section(s): ${extra[*]}"
    elif [ "${#missing[@]}" -gt 0 ]; then
        reason="missing C1 H2 section(s): ${missing[*]}"
    else
        reason="C1 H2 sections present but out of order (got: ${got[*]:-<none>})"
    fi

    echo "goalforge-section-lint: BLOCK — $f: $reason" >&2
    emit_gate_result "fail" "$reason" "$wp" "$feat_dir"
    return 2
}

case "${1:-}" in
    "") echo "usage: goalforge-section-lint.sh <overview.md>" >&2; exit 2 ;;
    *)  lint "$1"; exit $? ;;
esac
