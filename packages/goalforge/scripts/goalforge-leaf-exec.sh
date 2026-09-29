#!/usr/bin/env bash
# goalforge-leaf-exec.sh — the ONE pinned wrapper an admitted implement leg runs
# (wp-08; OQ4 (a) and its G3r3/G3r4 follow-ups; H1/H2, 2026-09-25).
#
# Usage (from the goalforge package root, exactly as the compiled workflow
# emits it; the brief is the WP overview.md at HEAD, written by the compile):
#
#     scripts/goalforge-leaf-exec.sh <task_class> <provider> <model> < <brief file>
#
# The argv is EXACTLY the admission row key. There is no hash argument and no
# table argument: an actor who can edit the leaf can also rewrite an argument in
# the emitted workflow file, so nothing on the command line is trusted. The
# expected `leaf`, `leaf_sha256` and `leaf_closure` are re-derived from the
# canonical admission table of the package that owns the admission script found
# at $(dirname "$0"). That script must be committed at its real path and
# byte-equal to its HEAD blob, so an UNTRACKED copied or hard-linked script
# elsewhere is refused; a COMMITTED shim passes that check and is refused by
# the guard-identity walk (verify_head_binding). The table admits only when its bytes are its committed HEAD content
# in a goalforge-guarded repository (goalforge-admission.py bind_table /
# verify_leaf / verify_head_binding). The leaf's real
# path must lie under the leaf root, it must hash to the recorded value, and
# every file under its directory tree must match the closure manifest, or this
# exits 2 WITHOUT executing it.
#
# The leaf runs per leaf-interface v1 §3:
#     <leaf> --model <model> --provider <provider> --prompt <brief> --output <tmp file>
# with the brief (stdin, modulo one trailing newline) as the `--prompt` VALUE,
# as goalforge-second-opinion.sh passes its payload. A brief over that script's
# MAX_PAYLOAD_CEILING raw bytes (one argv string must fit MAX_ARG_STRLEN) or
# containing NUL (argv cannot carry it) exits 2, leaf not run. No `--effort`:
# the leaf runs at its provider default. The --output file is printed to stdout.
#
# Exit: the leaf's status; 2 on any refusal (wrong argv, brief, table, HEAD
# binding, leaf root, hash, closure).
set -uo pipefail

if [[ $# -ne 3 ]]; then
    echo "goalforge-leaf-exec: refused — expected exactly the admission row key" \
         "<task_class> <provider> <model>, got $# argument(s)" >&2
    exit 2
fi

refuse() { echo "goalforge-leaf-exec: refused — $1; the leaf was not executed" >&2; exit 2; }

# The brief cap has ONE home: goalforge-second-opinion.sh's MAX_PAYLOAD_CEILING.
CEILING_EXPR="$(sed -n 's/^MAX_PAYLOAD_CEILING=\$((\([0-9 *]*\)))$/\1/p' \
    "$(dirname "$0")/goalforge-second-opinion.sh" 2>/dev/null)"
[[ -n "$CEILING_EXPR" ]] || refuse "cannot read MAX_PAYLOAD_CEILING from goalforge-second-opinion.sh"
MAX_BRIEF_BYTES=$(( CEILING_EXPR ))

WORK="$(mktemp -d)" || refuse "cannot create a temp directory"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/brief" || refuse "cannot read the brief from stdin"
BRIEF_BYTES=$(wc -c < "$WORK/brief")
if (( BRIEF_BYTES > MAX_BRIEF_BYTES )); then
    refuse "the brief is $BRIEF_BYTES bytes, over the brief cap of $MAX_BRIEF_BYTES (MAX_PAYLOAD_CEILING)"
fi
if (( $(tr -d '\000' < "$WORK/brief" | wc -c) != BRIEF_BYTES )); then
    refuse "the brief contains a NUL byte, which an argv value cannot carry"
fi

LEAF="$(python3 "$(dirname "$0")/goalforge-admission.py" --verify-leaf "$1" "$2" "$3")" \
    || refuse "the admission check failed"

# $(...) strips every trailing newline; the sentinel keeps all but ONE.
PROMPT="$(cat "$WORK/brief"; printf x)"
PROMPT="${PROMPT%x}"
PROMPT="${PROMPT%$'\n'}"

"$LEAF" --model "$3" --provider "$2" --prompt "$PROMPT" --output "$WORK/output"
LEAF_STATUS=$?
[[ -f "$WORK/output" ]] && cat "$WORK/output"
exit "$LEAF_STATUS"
