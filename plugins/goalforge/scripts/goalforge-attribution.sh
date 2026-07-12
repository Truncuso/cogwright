#!/usr/bin/env bash
# sdd-attribution.sh — emit the decision / answered-question attribution stamp.
#
# Single source of the stamp format, shared by the ledger writer
# (sdd-transition.sh) and the findings.md authors (sdd-harden). Reuses
# ~/.claude/scripts/handoff-env.sh for {session,model,provider}; never reinvents
# the extraction.
#
# Usage:
#   sdd-attribution.sh [--mode human|auto] [--actor <id>] [--agent <id>] [--json]
#
# Default output — a one-line render form for a findings.md "Resolved-by" cell:
#   auto · <provider>/<model> · session:<id8>
#   human · <git user.name> · session:<id8>
# --json: {mode,actor,session,model,provider,agent}
#
# Degrade-not-block: every extraction failure resolves to "unknown"; this script
# NEVER exits non-zero on a missing identifier (no `set -e`).
set -uo pipefail

MODE="auto"; ACTOR=""; AGENT=""; JSON=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)  MODE="${2:-auto}"; shift 2 ;;
        --actor) ACTOR="${2:-}"; shift 2 ;;
        --agent) AGENT="${2:-}"; shift 2 ;;
        --json)  JSON=1; shift ;;
        *)       shift ;;
    esac
done

# ── session / model / provider via the existing extractor (reuse, not reinvent)
ENV_SCRIPT="$HOME/.claude/scripts/handoff-env.sh"
SESSION="unknown"; MODEL="unknown"; PROVIDER="unknown"
if [[ -f "$ENV_SCRIPT" ]]; then
    ENV_JSON="$(bash "$ENV_SCRIPT" --json 2>/dev/null || true)"
    if [[ -n "$ENV_JSON" ]]; then
        SESSION="$( printf '%s' "$ENV_JSON" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)"
        MODEL="$(   printf '%s' "$ENV_JSON" | jq -r '.model      // "unknown"' 2>/dev/null || echo unknown)"
        PROVIDER="$(printf '%s' "$ENV_JSON" | jq -r '.provider   // "unknown"' 2>/dev/null || echo unknown)"
    fi
fi
[[ -z "$SESSION"  ]] && SESSION="unknown"
[[ -z "$MODEL"    ]] && MODEL="unknown"
[[ -z "$PROVIDER" ]] && PROVIDER="unknown"

# ── mode-normalized actor ────────────────────────────────────────────────────
if [[ "$MODE" == "human" ]]; then
    NAME="$(git config user.name 2>/dev/null || true)"
    [[ -z "$NAME" ]] && NAME="unknown"
    ACTOR="human:$NAME"
else
    MODE="auto"
    [[ -z "$ACTOR" ]] && ACTOR="auto"
fi

ID8="${SESSION:0:8}"   # short session for the render form

if [[ "$JSON" -eq 1 ]]; then
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg mode "$MODE" --arg actor "$ACTOR" --arg session "$SESSION" \
              --arg model "$MODEL" --arg provider "$PROVIDER" --arg agent "$AGENT" \
              '{mode:$mode,actor:$actor,session:$session,model:$model,provider:$provider,agent:$agent}'
    else
        printf '{"mode":"%s","actor":"%s","session":"%s","model":"%s","provider":"%s","agent":"%s"}\n' \
            "$MODE" "$ACTOR" "$SESSION" "$MODEL" "$PROVIDER" "$AGENT"
    fi
elif [[ "$MODE" == "human" ]]; then
    printf 'human · %s · session:%s\n' "${ACTOR#human:}" "$ID8"
else
    printf 'auto · %s/%s · session:%s\n' "$PROVIDER" "$MODEL" "$ID8"
fi
