#!/usr/bin/env bash
# Regression test for goalforge-single-writer.sh — the ctx_patch write surface.
# Focus: mcp__lean-ctx__ctx_patch (and ctx_call{name:"ctx_patch"}) must be held
# to the SAME single-writer guarantee as Edit/Write/MultiEdit. Hermetic: every
# fixture lives under a trap-cleaned tmpdir and every run overrides HOME to a
# fake home inside it, so no case can resolve against the real ~/.claude/plans.
#
# Contract asserted: exit 2 + a "<field>|<file>"-derived stderr message for a
# blocking op; exit 0 and silence otherwise.
#
# wp-01/C1 retired task-*.md and brief-*.md entirely (no task/brief files, no
# briefs) — the hook (and this test) scope only overview.md/spec.md, and the
# brief-immutability cases are gone with the machinery they guarded.
#
# Cases:
#   1: ctx_patch old/new edit of status: on a scoped WP file        -> BLOCK
#   2: ctx_patch old/new edit of body prose                         -> ALLOW
#   3: ctx_patch on an unscoped path                                -> ALLOW
#   4: ctx_call-wrapped ctx_patch mutating status:                  -> BLOCK
#   5: ctx_patch op=create on a nonexistent path                    -> ALLOW
#   6: ctx_patch set_line carrying "status: ready"                  -> BLOCK
#   7: ctx_patch ops[] with the offending op SECOND                 -> BLOCK
#   8: ctx_patch find/replace spelling (not old_text/new_text)      -> BLOCK
#   9: ctx_patch op=delete on a scoped WP file (un-simulatable)     -> ALLOW
#  10: ctx_call naming a NON-ctx_patch inner tool                   -> ALLOW
#  11: goalforge-single-writer.sh --self-test                       -> exit 0
#  12: gate.result trace emission (T22) — a real block through a fresh
#      $SDD_PLANS_DIR appends a schema-valid gate.result row (wp/gate/result/
#      reason) to that feature's trace-events.jsonl.
#  13: human_required (ticket-72 monotonicity): null -> "<reason>"    -> ALLOW
#  14: human_required: an already-set reason -> a different value     -> BLOCK
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/goalforge-single-writer.sh"
PASS=0
FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── fixtures ─────────────────────────────────────────────────────────────────

FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME/.claude/plans/feat/wp-01" "$FAKE_HOME/.claude/plans/feat/wp-02"

wp_file="$FAKE_HOME/.claude/plans/feat/wp-01/spec.md"
printf -- '---\ntitle: Old Title\nstatus: hardened\ngoal_approved_version: 1\n---\nbody prose here\n' > "$wp_file"

overview_file="$FAKE_HOME/.claude/plans/feat/wp-01/overview.md"
printf -- '---\ntitle: Feature\nstatus: hardened\n---\nbody\n' > "$overview_file"

# Unscoped: right basename shape, but outside every plans root.
unscoped_file="$WORK/spec.md"
printf -- '---\nstatus: hardened\n---\nbody\n' > "$unscoped_file"

new_file="$FAKE_HOME/.claude/plans/feat/wp-02/overview.md"   # never created

# run_hook <json-payload> — rc via return; stdout/stderr captured in $WORK.
run_hook() {
    local payload="$1" rc=0
    printf '%s' "$payload" | HOME="$FAKE_HOME" bash "$HOOK" >"$WORK/out" 2>"$WORK/err" || rc=$?
    return $rc
}

expect() { # <label> <want-rc> <payload>
    local rc=0
    run_hook "$3" || rc=$?
    if [ "$rc" = "$2" ]; then
        ok "$1"
    else
        no "$1 — exit $rc (want $2); stderr: $(cat "$WORK/err")"
    fi
}

# ── (1) ctx_patch old/new edit of status: on a scoped WP file -> BLOCK ───────

payload="$(command jq -n --arg fp "$wp_file" \
    '{tool_name:"mcp__lean-ctx__ctx_patch", tool_input:{path:$fp, op:"replace_unique",
      old_text:"status: hardened", new_text:"status: ready"}}')"
expect "1: ctx_patch status mutation on scoped WP -> BLOCK (exit 2)" 2 "$payload"
grep -q "goalforge-transition.sh" "$WORK/err" \
    && ok "1: stderr names the sanctioned writer" \
    || no "1: stderr missing sanctioned-writer mention ($(cat "$WORK/err"))"

# ── (2) ctx_patch old/new edit of body prose -> ALLOW ────────────────────────

payload="$(command jq -n --arg fp "$wp_file" \
    '{tool_name:"mcp__lean-ctx__ctx_patch", tool_input:{path:$fp, op:"replace_unique",
      old_text:"body prose here", new_text:"revised prose here"}}')"
expect "2: ctx_patch body-prose edit -> ALLOW (exit 0)" 0 "$payload"

# ── (3) ctx_patch on an unscoped path -> ALLOW ───────────────────────────────

payload="$(command jq -n --arg fp "$unscoped_file" \
    '{tool_name:"mcp__lean-ctx__ctx_patch", tool_input:{path:$fp, op:"replace_unique",
      old_text:"status: hardened", new_text:"status: ready"}}')"
expect "3: ctx_patch on unscoped path -> ALLOW (exit 0)" 0 "$payload"

# ── (4) ctx_call-wrapped ctx_patch mutating status: -> BLOCK ─────────────────
# The bare-value form, so this also proves the wrapped path reaches the real
# simulate-and-compare and not a snippet-level string match.

payload="$(command jq -n --arg fp "$overview_file" \
    '{tool_name:"mcp__lean-ctx__ctx_call", tool_input:{name:"ctx_patch", arguments:{
      path:$fp, op:"replace_unique", old_text:"hardened", new_text:"ready"}}}')"
expect "4: ctx_call-wrapped ctx_patch status mutation -> BLOCK (exit 2)" 2 "$payload"

# ── (5) ctx_patch op=create on a nonexistent path -> ALLOW (scaffolding) ─────

payload="$(command jq -n --arg fp "$new_file" \
    '{tool_name:"mcp__lean-ctx__ctx_patch", tool_input:{path:$fp, op:"create",
      new_text:"---\nstatus: draft\n---\nbody\n"}}')"
expect "5: ctx_patch op=create on nonexistent path -> ALLOW (exit 0)" 0 "$payload"
[ -f "$new_file" ] && no "5: fixture leaked — hook must not create files" || :

# ── (6) set_line carrying "status: ready" -> BLOCK (conservative fallback) ───

payload="$(command jq -n --arg fp "$wp_file" \
    '{tool_name:"mcp__lean-ctx__ctx_patch", tool_input:{path:$fp, op:"set_line",
      line:3, new_text:"status: ready"}}')"
expect "6: ctx_patch set_line carrying 'status:' -> BLOCK (exit 2)" 2 "$payload"

# ── (7) ops[] with the offending op SECOND -> BLOCK ──────────────────────────

payload="$(command jq -n --arg fp "$wp_file" --arg un "$unscoped_file" \
    '{tool_name:"mcp__lean-ctx__ctx_patch", tool_input:{ops:[
      {path:$un, op:"replace_unique", old_text:"status: hardened", new_text:"status: ready"},
      {path:$fp, op:"replace_unique", old_text:"title: Old Title", new_text:"title: New Title"},
      {path:$fp, op:"replace_unique", old_text:"goal_approved_version: 1", new_text:"goal_approved_version: 2"}
    ]}}')"
expect "7: ctx_patch ops[] with a non-first offending op -> BLOCK (exit 2)" 2 "$payload"
grep -q "goal_approved_version" "$WORK/err" \
    && ok "7: stderr names the offending field (goal_approved_version)" \
    || no "7: stderr named the wrong field ($(cat "$WORK/err"))"

# ── (8) find/replace spelling of the same op -> BLOCK ────────────────────────

payload="$(command jq -n --arg fp "$overview_file" \
    '{tool_name:"ctx_patch", tool_input:{path:$fp, find:"status: hardened", replace:"status: verified"}}')"
expect "8: ctx_patch find/replace spelling -> BLOCK (exit 2)" 2 "$payload"

# ── (9) op=delete on a scoped WP file -> ALLOW (un-simulatable, no new text) ─

payload="$(command jq -n --arg fp "$wp_file" \
    '{tool_name:"mcp__lean-ctx__ctx_patch", tool_input:{path:$fp, op:"delete", line:3}}')"
expect "9: ctx_patch op=delete (un-simulatable, no new text) -> ALLOW (exit 0)" 0 "$payload"

# ── (10) ctx_call naming a non-ctx_patch inner tool -> ALLOW ────────────────

payload="$(command jq -n --arg fp "$wp_file" \
    '{tool_name:"mcp__lean-ctx__ctx_call", tool_input:{name:"ctx_read", arguments:{path:$fp}}}')"
expect "10: ctx_call naming a non-ctx_patch inner tool -> ALLOW (exit 0)" 0 "$payload"

# ── (11) the hook's own internal self-test still passes ─────────────────────

rc=0; HOME="$FAKE_HOME" bash "$HOOK" --self-test >"$WORK/selftest.out" 2>&1 || rc=$?
[ "$rc" = "0" ] && ok "11: --self-test passes (exit 0)" \
    || no "11: --self-test exit $rc; $(cat "$WORK/selftest.out")"

# ── (12) gate.result trace emission (T22) ────────────────────────────────────
# Drive a real block through a throwaway $SDD_PLANS_DIR (not $FAKE_HOME) so the
# emitted row lands in a trace-events.jsonl this test alone reads, and assert
# it validates against trace-events.md's gate.result contract (wp/gate/result/
# reason all required, result in pass|fail|warn).
trace_root="$WORK/tracehome/plans"
mkdir -p "$trace_root/tracefeat/wp-09"
trace_file="$trace_root/tracefeat/wp-09/overview.md"
printf -- '---\nstatus: hardened\n---\nbody\n' > "$trace_file"
payload="$(command jq -n --arg fp "$trace_file" \
    '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: hardened", new_string:"status: ready"}}')"
printf '%s' "$payload" | SDD_PLANS_DIR="$trace_root" bash "$HOOK" >/dev/null 2>&1
trace="$trace_root/tracefeat/trace-events.jsonl"
if [ -f "$trace" ] && command jq -e \
    'select(.type=="gate.result" and .gate=="single-writer" and .result=="fail" and .wp=="wp-09" and (.reason|length>0))' \
    "$trace" >/dev/null 2>&1; then
    ok "12: block -> gate.result{gate:single-writer,result:fail,wp:wp-09} emitted"
else
    no "12: block -> gate.result row missing/malformed ($(cat "$trace" 2>/dev/null))"
fi

# ── (13) human_required null -> "<reason>" -> ALLOW (the one sanctioned SET) ─

hr_file="$FAKE_HOME/.claude/plans/feat/wp-hr/overview.md"
mkdir -p "$(dirname "$hr_file")"
printf -- '---\ntitle: HR\nhuman_required: null\n---\nbody\n' > "$hr_file"
payload="$(command jq -n --arg fp "$hr_file" \
    '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"human_required: null", new_string:"human_required: \"schema migration\""}}')"
expect "13: human_required null -> \"<reason>\" -> ALLOW (exit 0)" 0 "$payload"

# ── (14) human_required already set -> a different value -> BLOCK (monotonic) ─

printf -- '---\ntitle: HR\nhuman_required: "old reason"\n---\nbody\n' > "$hr_file"
payload="$(command jq -n --arg fp "$hr_file" \
    '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"human_required: \"old reason\"", new_string:"human_required: \"new reason\""}}')"
expect "14: human_required set -> different value -> BLOCK (exit 2)" 2 "$payload"
grep -q "monotonic" "$WORK/err" \
    && ok "14: stderr names the monotonicity rule" \
    || no "14: stderr missing monotonicity mention ($(cat "$WORK/err"))"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
