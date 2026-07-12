#!/usr/bin/env bash
# sdd-goal-eval.sh — thin wrapper over sdd-goal-eval.py (the pure goal router).
#
# Usage:
#   sdd-goal-eval.sh --wp <wp-overview.md> [--spec <feature-spec.md>]
#
# Prints the verdict JSON {met, reason, strategy, directive?} and exits:
#   0  → goal met        (deterministic/numeric only)
#   1  → goal not met     (deterministic/numeric only)
#   2  → undecided here   (judge/human — a directive was returned for the agent)
#
# The script is PURE: it never dispatches a skill and never prompts. The
# sdd-execute agent acts on judge/human directives (design §4).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/sdd-goal-eval.py" "$@"
