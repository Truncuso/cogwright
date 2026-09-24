#!/usr/bin/env bash
# goalforge-leaf-exec.sh — the ONE pinned wrapper an admitted implement leg runs
# (wp-08; OQ4 (a) and its G3r3/G3r4 follow-ups).
#
# Usage (from the goalforge package root, exactly as the compiled workflow
# emits it):
#
#     scripts/goalforge-leaf-exec.sh <task_class> <provider> <model>
#
# The argv is EXACTLY the admission row key. There is no hash argument and no
# table argument: an actor who can edit the leaf can also rewrite an argument in
# the emitted workflow file, so nothing on the command line is trusted. The
# expected `leaf` and `leaf_sha256` are re-derived from the admission table
# resolved script-relative below, and only when that table's bytes are its
# committed HEAD content in a goalforge-guarded repository
# (goalforge-admission.py verify_leaf / verify_head_binding). The leaf's real
# path must lie under the leaf root and must hash to the recorded value, or
# this exits 2 WITHOUT executing it. Otherwise the leaf runs (no arguments,
# stdin inherited) and its exit status is returned.
#
# Exit: the leaf's status; 2 on any refusal (wrong argv, table, HEAD binding,
# leaf root, hash).
set -uo pipefail

if [[ $# -ne 3 ]]; then
    echo "goalforge-leaf-exec: refused — expected exactly the admission row key" \
         "<task_class> <provider> <model>, got $# argument(s)" >&2
    exit 2
fi

TABLE="$(dirname "$0")/../references/admitted-providers.yaml"

LEAF="$(python3 "$(dirname "$0")/goalforge-admission.py" --verify-leaf "$TABLE" "$1" "$2" "$3")" || {
    echo "goalforge-leaf-exec: refused — the leaf was not executed" >&2
    exit 2
}

"$LEAF"
exit $?
