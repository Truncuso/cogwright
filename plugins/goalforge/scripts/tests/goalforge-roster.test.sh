#!/usr/bin/env bash
# goalforge-roster.test.sh — wp-02 T1 / behavior b1.
#
# Admission contract for the generic agent roster under agents/:
#   name, description, model in {sonnet, opus}, effort in {low, medium, high},
#   a skills: list, an expertise: slot, no absolute home path, and a body
#   carrying ## Your Role, ## Mindset, ## Seniority, ## Return contract.
#
#   known-good: the four live roster files -> --check exits 0
#   known-bad:  six fixtures under evals/fixtures/roster/ (missing effort,
#               model fable, missing skills, missing expertise slot,
#               absolute /home path, frontmatter-only body) -> --check
#               exits 2
#
# `--check <file>` is the validator itself: it prints one reason per
# violation and exits 2, so the sabotage pair below is the same code path
# the roster is admitted by.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
ROSTER_DIR="$PKG/agents"
FIXTURES="$PKG/evals/fixtures/roster"

# ── validator ────────────────────────────────────────────────────────────
# Reads the YAML frontmatter (the block between the first two `---` lines)
# and the body. Prints violations; exit 0 = admissible, 2 = rejected.
check_file() {
    local f="$1" bad=0
    if [[ ! -f "$f" ]]; then
        echo "    no such roster file: $f"
        return 2
    fi

    local fm
    fm="$(awk 'NR==1 && $0!="---" {exit} NR==1 {next} /^---$/ {exit} {print}' "$f")"
    if [[ -z "$fm" ]]; then
        echo "    no YAML frontmatter"
        return 2
    fi

    grep -qE '^name: *[^ ]' <<<"$fm"        || { echo "    missing name:"; bad=1; }
    grep -qE '^description: *[^ ]' <<<"$fm" || { echo "    missing description:"; bad=1; }

    local model effort
    model="$(sed -n 's/^model: *//p' <<<"$fm" | head -1)"
    effort="$(sed -n 's/^effort: *//p' <<<"$fm" | head -1)"
    case "$model" in
        sonnet|opus) ;;
        "") echo "    missing model:"; bad=1 ;;
        *)  echo "    model not in {sonnet, opus}: $model"; bad=1 ;;
    esac
    case "$effort" in
        low|medium|high) ;;
        "") echo "    missing effort:"; bad=1 ;;
        *)  echo "    effort not in {low, medium, high}: $effort"; bad=1 ;;
    esac

    # skills: must be a non-empty list — flow `[a, b]` or block `- a` lines.
    if grep -qE '^skills: *\[[^]]+\]' <<<"$fm"; then
        :
    elif grep -qE '^skills: *$' <<<"$fm" \
         && sed -n '/^skills: *$/,/^[a-zA-Z]/p' <<<"$fm" | grep -qE '^ +- +[^ ]'; then
        :
    else
        echo "    missing or empty skills: list"
        bad=1
    fi

    # expertise: slot must exist — empty list or a placeholder list, filled
    # at dispatch. Presence, not contents, is the contract.
    grep -qE '^expertise:( |$)' <<<"$fm" || { echo "    missing expertise: slot"; bad=1; }

    # no absolute home path anywhere in the file (frontmatter or body).
    local hits
    hits="$(grep -nE '(^|[^A-Za-z0-9_.-])/(home|Users)/' "$f" || true)"
    if [[ -n "$hits" ]]; then
        echo "    absolute home path: $(head -1 <<<"$hits")"
        bad=1
    fi

    # body: the four sections every dispatched roster agent is read for.
    # Frontmatter alone is not a roster file — without these the agent has no
    # role, no stance, no seniority, and no typed return the caller can
    # consume as DATA. Headings are pinned to the live agents/*.md wording.
    local sec
    for sec in '## Your Role' '## Mindset' '## Seniority' '## Return contract'; do
        grep -qxF "$sec" "$f" || { echo "    missing required section: $sec"; bad=1; }
    done

    [[ "$bad" -eq 0 ]] && return 0 || return 2
}

if [[ "${1:-}" == "--check" ]]; then
    check_file "${2:?--check needs a file}"
    exit $?
fi

# ── harness ──────────────────────────────────────────────────────────────
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SELF="${BASH_SOURCE[0]}"

# known-good — the four roster files the chain dispatches to.
for name in implementer reviewer evaluation-expert researcher; do
    f="$ROSTER_DIR/$name.md"
    OUT="$(bash "$SELF" --check "$f" 2>&1)"; RC=$?
    if [[ "$RC" -eq 0 ]]; then
        ok "roster $name.md admissible (exit 0)"
    else
        bad "roster $name.md admissible (rc=$RC)${OUT:+ — $OUT}"
    fi
done

# the roster is exactly these four — a fifth file would be dispatched to
# without ever passing through this contract.
EXTRA="$(cd "$ROSTER_DIR" 2>/dev/null && ls *.md 2>/dev/null \
         | grep -vxE 'implementer.md|reviewer.md|evaluation-expert.md|researcher.md' || true)"
if [[ -z "$EXTRA" ]]; then
    ok "agents/ holds exactly the four roster files"
else
    bad "agents/ holds exactly the four roster files (unexpected: $(tr '\n' ' ' <<<"$EXTRA"))"
fi

# the evaluation-expert carries the gate C rubric (it was deleted from
# verify/SKILL.md in T4 — if it lives nowhere, gate C has no rubric).
EE="$ROSTER_DIR/evaluation-expert.md"
if grep -q 'PASS' "$EE" && grep -q 'BLOCK' "$EE" && grep -qi 'rubric' "$EE" \
   && grep -qi 'evidence' "$EE"; then
    ok "evaluation-expert.md carries the gate C rubric (verdict PASS|BLOCK, quoted evidence)"
else
    bad "evaluation-expert.md carries the gate C rubric (verdict PASS|BLOCK, quoted evidence)"
fi

# known-bad ---------------------------------------------------------------
# Each fixture must exist AND be rejected for its OWN defect: a missing
# fixture also exits 2 ("no such roster file"), so exit 2 alone is a check
# that cannot fail. The reason pattern pins the first violation line.
reason_for() {
    case "$1" in
        missing-effort)     echo 'missing effort:' ;;
        model-fable)        echo 'model not in \{sonnet, opus\}: fable' ;;
        missing-skills)     echo 'missing or empty skills: list' ;;
        missing-expertise)  echo 'missing expertise: slot' ;;
        absolute-home-path) echo 'absolute home path:' ;;
        missing-body)       echo 'missing required section: ## Your Role' ;;
    esac
}

for fx in missing-effort model-fable missing-skills missing-expertise absolute-home-path missing-body; do
    f="$FIXTURES/$fx.md"
    if [[ ! -f "$f" ]]; then
        bad "known-bad $fx.md: fixture missing at $f"
        continue
    fi
    OUT="$(bash "$SELF" --check "$f" 2>&1)"; RC=$?
    FIRST="$(head -1 <<<"$OUT" | sed 's/^ *//')"
    WANT="$(reason_for "$fx")"
    if [[ "$RC" -ne 2 ]]; then
        bad "known-bad $fx.md: expected exit 2, got $RC${OUT:+ — $OUT}"
    elif ! grep -qE "$WANT" <<<"$FIRST"; then
        bad "known-bad $fx.md: exit 2 for the wrong reason — want /$WANT/, got: $FIRST"
    else
        ok "known-bad $fx.md: exit 2 ($FIRST)"
    fi
done

echo
echo "goalforge-roster.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
