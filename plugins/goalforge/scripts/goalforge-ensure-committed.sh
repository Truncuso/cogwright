#!/usr/bin/env bash
# Fail-closed: no uncommitted artifacts under the feature path. Branch-agnostic.
set -uo pipefail
FEATURE_DIR="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1")"
REPO="$(git -C "$FEATURE_DIR" rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo: $FEATURE_DIR" >&2; exit 0; }
DIRTY="$(git -C "$REPO" status --porcelain -- "$FEATURE_DIR")"
if [ -n "$DIRTY" ]; then echo "UNCOMMITTED feature artifacts under $FEATURE_DIR:" >&2; echo "$DIRTY" >&2; exit 1; fi
exit 0
