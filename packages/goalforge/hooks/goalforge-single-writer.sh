#!/usr/bin/env bash
# goalforge-single-writer.sh — PreToolUse hard guard: block direct tool-surface
# mutation of the `status:`/`goal_approved_version:`/`human_required:`
# frontmatter fields (C2) on plan/WP files. Single-writer enforcement for
# those three fields.
#
# DISCRIMINATOR (why this hook only ever sees Edit/Write/MultiEdit): a
# PreToolUse payload carries only the tool call (tool_name + tool_input) — it
# has NO caller attribution, no skill/script name, no call stack. The
# sanctioned writers (goalforge-transition.sh, goalforge-goal-hash.sh) mutate files via
# `Bash` (sed -i / python / direct file write inside a shell command), never
# via the Edit/Write/MultiEdit tool surface — so they never trip this
# matcher's tool_name filter. That is an exemption BY CONSTRUCTION, not a
# name-based allowlist this hook maintains: there is nothing to inspect that
# would tell an Edit-tool call from a "trusted" one, so the only honest gate
# is the tool surface itself. Do not attempt to special-case a "trusted
# caller" here — the payload does not carry that information.
#
# DIVISION OF LABOR: hooks/goalforge-transition-guard.sh is a separate guard
# (wired PreToolUse, matcher Edit only) over edge *legality* (is old-status ->
# new-status a valid SDD transition). THIS hook owns hard field-mutation
# protection across ALL THREE tools — it does not
# care whether the transition is legal, only whether the write is coming
# through a tool surface instead of the sanctioned Bash-path writers.
#
# SCOPE: any resolved PLANS_ROOT — $SDD_PLANS_DIR, else <git-root>/plans/**,
# else ~/.claude/plans/** (resolution owned by the sourced
# goalforge-plans-root.sh; never re-implemented here, and never hardcoded to
# $HOME/.claude/plans alone — that was the precedent bug
# in goalforge-frontmatter-touch.sh), basename overview.md or spec.md
# (wp-01/C1 retired task-*.md and brief-*.md — no basename for either is
# scoped here any more).
#
# SCAFFOLDING EXEMPTION (uniform across Write/Edit/MultiEdit): if the target
# file does NOT exist on disk at check time, ALLOW regardless of tool or
# content. Stamping an initial `status:` into a brand-new plan/WP file
# (template scaffolding) is authoring, not mutation — there is no existing
# field value to protect. The exemption covers ONLY creation: the exists-check
# runs fresh on every call, so a create-then-edit-status sequence is NOT
# exempt — by the time the follow-up Edit/MultiEdit/Write arrives the file
# exists, and a status:/goal_approved_version: value change blocks as usual.
#
# SIMULATE-AND-COMPARE (Edit/MultiEdit): a payload's old_string/new_string are
# SNIPPETS, not field values — diffing them directly both misses real
# mutations (neither snippet mentions "status:" but the substitution still
# lands on a status: line) and false-positives on body prose that merely
# starts with "status:". Instead this hook reads the REAL on-disk file,
# confirms old_string actually occurs in it (if not, the real Edit/MultiEdit
# would fail anyway -> ALLOW), then SIMULATES the substitution against the
# full file content with the same semantics as the real tool: Edit replaces
# the FIRST occurrence; MultiEdit applies each edit in the payload
# cumulatively in order, replacing all occurrences only when that edit's
# `replace_all` is true, first occurrence otherwise. Both the real and the
# simulated content are then scoped to the FRONTMATTER REGION ONLY (between
# the leading `---` fence and the next `---` fence) before extracting
# status:/goal_approved_version: — this is what makes the check both
# unbypassable (it mirrors what actually lands on disk) and free of the
# body-prose false positive (a body line is never in scope).
#
# Substitution mechanism: quoted-variable bash parameter/pattern
# substitution — `${content/"$old"/"$new"}` (first occurrence) and
# `${content//"$old"/"$new"}` (all occurrences, MultiEdit replace_all:true
# only) — and `case "$content" in *"$old"*)` for the occurs-in-file check.
# Quoting $old/$new inside the pattern forces bash to treat them as LITERAL
# strings (defeats glob metacharacters like `*`/`?`/`[` that could appear in
# arbitrary payload text), and this form is 8-bit/newline-safe for the
# multi-line snippets Edit payloads carry — no snippet text is ever
# interpolated into sed, a regex, or an external interpreter's code (a python
# heredoc reading from environment variables was considered but the pure-bash
# form needs no additional dependency and has no code-interpolation surface
# at all).
#
# CTX_PATCH (lean-ctx MCP write surface): the Edit/Write/MultiEdit matcher is
# not the whole tool surface — `mcp__lean-ctx__ctx_patch` writes files too, and
# `mcp__lean-ctx__ctx_call{name:"ctx_patch"}` proxies it. Both are accepted here
# (bare spellings included) and mapped onto the SAME simulate-and-compare
# machinery, so the single-writer guarantee is tool-agnostic. One level of
# ctx_call unwrap only — ctx_call cannot invoke itself. The payload is
# normalized into a uniform op list (an explicit `ops[]`, else the top-level
# {path, old_text|find, new_text|replace} as a single op), and EVERY op is
# checked against ITS OWN path: the first offending op blocks the whole call
# (the real call is not atomic per-op, so one blocking op is enough).
#
# Per-op classes:
#   reconstructable old/new (old_text|find + new_text|replace) -> the Edit
#     simulation verbatim (replace_all does the all-occurrences form).
#   op=create on a nonexistent path -> the scaffolding exemption above.
#   op=delete, or any op WITHOUT a reconstructable old (set_line,
#     replace_lines, insert_after, replace_symbol, ...) -> UN-SIMULATABLE: the
#     real post-write content cannot be derived from the payload, so the
#     fallback is a CONSERVATIVE scan of the op's new text for a protected
#     `<field>:` key ($FIELDS — the same list, not a new one): a set_line
#     carrying `status: ready` blocks; an op carrying no protected key allows.
#     This is deliberately weaker than simulate-and-compare (it cannot see a
#     bare-value substitution landing on a status: line), because the payload
#     genuinely does not say what lands on disk — allowing is the zero-breakage
#     side of that ambiguity.
#
# ZERO-BREAKAGE: any internal error (malformed JSON, missing jq, unreadable
# file) exits 0 — this hook must never block because it broke internally.
# The ONLY non-zero exit is exit 2 for a confirmed direct mutation of
# status:/goal_approved_version: on an in-scope file.
#
# Usage:
#   <PreToolUse JSON on stdin> | goalforge-single-writer.sh
#   goalforge-single-writer.sh --self-test
set -uo pipefail

# Hook dir via readlink -f so the dotfiles-symlink route (a symlink in
# ~/.claude/hooks/ pointing into the package) still finds the sibling helper.
HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
# shellcheck source=./goalforge-plans-root.sh
. "$HOOK_DIR/goalforge-plans-root.sh" 2>/dev/null || {
    echo "goalforge-single-writer: goalforge-plans-root.sh not found beside the hook — skipping (zero-breakage)" >&2
    exit 0
}

FIELDS="status goal_approved_version human_required"

# ── path scoping ─────────────────────────────────────────────────────────────

# True (0) iff $1's basename is a protected plan/WP file AND $1 resolves under
# a plans root (goalforge-plans-root.sh owns the resolution order).
is_scoped() {
    local fp="$1" bn
    [ -n "$fp" ] || return 1
    bn="$(basename -- "$fp")"
    case "$bn" in
        overview.md|spec.md) : ;;
        *) return 1 ;;
    esac
    goalforge_under_plans_root "$fp"
}

# ── frontmatter field extraction ────────────────────────────────────────────

# Prints only the frontmatter region of $1 (the text strictly between the
# leading `---` fence and the next `---` fence, exclusive of both fence
# lines), or empty if no closed frontmatter block is found. Scoping
# status:/goal_approved_version: extraction to this region — rather than the
# whole file/snippet — is what keeps a body line like "status: done (see
# checkpoint)" from tripping the guard.
extract_frontmatter() {
    local text="$1" line started=0 out=""
    while IFS= read -r line; do
        if [ "$line" = "---" ]; then
            if [ "$started" -eq 0 ]; then
                started=1
                continue
            else
                break
            fi
        fi
        [ "$started" -eq 1 ] && out="${out}${line}"$'\n'
    done <<< "$text"
    printf '%s' "$out"
}

# Prints the trimmed, unquoted value of the first `<field>:` line in $1
# (text on stdin-like arg — callers pass frontmatter-scoped text via
# extract_frontmatter so a body line is never in scope), or empty if absent.
extract_value() {
    local text="$1" field="$2" line val
    line="$(printf '%s\n' "$text" | grep -m1 -E "^[[:space:]]*${field}:" 2>/dev/null)" || return 0
    [ -z "$line" ] && return 0
    val="$(printf '%s' "$line" | sed -E "s/^[[:space:]]*${field}:[[:space:]]*//")"
    val="$(printf '%s' "$val" | sed -E 's/^["'"'"']//; s/["'"'"']$//; s/[[:space:]]+$//')"
    printf '%s' "$val"
}

# True (empty string or the literal unquoted "null") iff $1 is human_required's
# unset state.
hr_is_null() {
    local v="$1"
    [ -z "$v" ] || [ "$v" = "null" ]
}

# Exit 0 (true) iff old->new for human_required is the ONE sanctioned
# transition (ticket-72): null -> "<reason>". human_required is monotonic —
# an agent may SET it, never clear or weaken it. Any other change (removal,
# reset to null, editing an already-set reason) is a violation.
human_required_violates_monotonicity() {
    local oldval="$1" newval="$2"
    hr_is_null "$oldval" || return 0     # old was already set -> any change violates
    hr_is_null "$newval" && return 0     # new is still null (or field removed) -> not a SET
    return 1                              # null -> "<reason>" -> allowed
}

# Exit 0 (true) iff $field appears in $old with a value, and its value in
# $new differs (including "absent in new" = differs). human_required gets
# monotonic-set semantics instead of a plain diff (see
# human_required_violates_monotonicity).
field_changed() {
    local old="$1" new="$2" field="$3" oldval newval
    oldval="$(extract_value "$old" "$field")"
    newval="$(extract_value "$new" "$field")"
    if [ "$field" = "human_required" ]; then
        [ "$oldval" = "$newval" ] && return 1
        human_required_violates_monotonicity "$oldval" "$newval"
        return $?
    fi
    [ -z "$oldval" ] && return 1        # field not present in old -> N/A
    [ "$oldval" != "$newval" ]
}

# Prints the first field name (of $FIELDS) that changed between $1(old) and
# $2(new), or empty if none.
changed_field() {
    local old="$1" new="$2" f
    for f in $FIELDS; do
        if field_changed "$old" "$new" "$f"; then
            printf '%s' "$f"
            return 0
        fi
    done
    return 1
}

# ── ctx_patch normalization ──────────────────────────────────────────────────

# Shared jq `def`s for the lean-ctx write surface. Kept inline (this package
# ships portable — it never sources a helper from outside its own hooks dir).
#   cp_bare  — strip a leading "mcp__lean-ctx__" from a string, else pass through.
#   cp_str   — coerce a non-string (or absent) value to "".
#   cp_tool  — the EFFECTIVE tool name: for ctx_call, .tool_input.name; else the
#              outer tool_name. Bare-ified either way.
#   cp_input — the EFFECTIVE tool_input: for ctx_call, .tool_input.arguments;
#              else the outer tool_input. Non-objects become {} so a malformed
#              payload yields an empty op list rather than a jq error.
#   cp_ops   — the uniform op list: {path, op, old, new} per op, paths falling
#              back to the top-level .path, old = old_text|find, new =
#              new_text|replace.
CTXP_JQ='
def cp_bare: if type == "string" and startswith("mcp__lean-ctx__") then sub("^mcp__lean-ctx__";"") else . end;
def cp_str: if type == "string" then . else "" end;
def cp_outer: (.tool_name? // "") | cp_bare;
def cp_tool: (cp_outer) as $o | if $o == "ctx_call" then ((.tool_input.name? // "") | cp_bare) else $o end;
def cp_input: (cp_outer) as $o
  | (if $o == "ctx_call" then .tool_input.arguments? else .tool_input? end) as $t
  | if ($t | type) == "object" then $t else {} end;
def cp_ops: cp_input as $i
  | (if (($i.ops?) | type) == "array" then [$i.ops[] | select(type == "object")] else [] end) as $ops
  | (if ($ops | length) > 0 then $ops else [$i] end)
  | map({
      path: ((.path? // $i.path?) | cp_str),
      op:   ((.op?) | cp_str),
      old:  ((.old_text? // .find?) | cp_str),
      new:  ((.new_text? // .replace?) | cp_str)
    });
'

# Prints the first field of $FIELDS whose `<field>:` key opens a line in $1, or
# empty. The conservative fallback for un-simulatable ops (see CTX_PATCH in the
# header) — a key-presence test on the payload's own new text, NOT a value diff
# against disk, because for these ops the on-disk result is unknowable here.
new_text_has_field() {
    local text="$1" f
    [ -n "$text" ] || return 1
    for f in $FIELDS; do
        if printf '%s\n' "$text" | grep -qE "^[[:space:]]*${f}:" 2>/dev/null; then
            printf '%s' "$f"
            return 0
        fi
    done
    return 1
}

# ctx_patch decision. Same stdout contract as decide(): "<field>|<file>" for a
# blocking op, nothing otherwise; never exits non-zero. Ops are checked in
# payload order and the FIRST offending one wins.
decide_ctx_patch() {
    local input="$1" eff ops entry path op old new existing simulated old_fm new_fm field
    eff="$(printf '%s' "$input" | command jq -r "${CTXP_JQ}"'cp_tool' 2>/dev/null)" || return 0
    [ "$eff" = "ctx_patch" ] || return 0
    ops="$(printf '%s' "$input" | command jq -c "${CTXP_JQ}"'cp_ops | .[]' 2>/dev/null)" || return 0
    [ -z "$ops" ] && return 0

    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        path="$(printf '%s' "$entry" | command jq -r '.path // empty' 2>/dev/null)" || return 0
        [ -z "$path" ] && continue
        is_scoped "$path" || continue

        # SCAFFOLDING EXEMPTION, uniform with the tool branches: a path that does
        # not exist yet is authoring (this is also where op=create lands).
        [ -f "$path" ] || continue

        op="$(printf '%s' "$entry" | command jq -r '.op // empty' 2>/dev/null)" || return 0
        old="$(printf '%s' "$entry" | command jq -r '.old // empty' 2>/dev/null)" || return 0
        new="$(printf '%s' "$entry" | command jq -r '.new // empty' 2>/dev/null)" || return 0

        if [ -n "$old" ]; then
            # Reconstructable: the Edit simulation, verbatim semantics.
            existing="$(cat "$path" 2>/dev/null)" || return 0
            case "$existing" in
                *"$old"*) : ;;
                *) continue ;;   # old text absent -> the real op would fail -> nothing to protect
            esac
            if [ "$op" = "replace_all" ]; then
                simulated="${existing//"$old"/"$new"}"
            else
                simulated="${existing/"$old"/"$new"}"
            fi
            old_fm="$(extract_frontmatter "$existing")"
            new_fm="$(extract_frontmatter "$simulated")"
            if field="$(changed_field "$old_fm" "$new_fm")" && [ -n "$field" ]; then
                printf '%s|%s' "$field" "$path"
                return 0
            fi
        else
            # Un-simulatable (op=delete, set_line, replace_lines, insert_after,
            # replace_symbol, ...): conservative protected-key scan of new text.
            if field="$(new_text_has_field "$new")" && [ -n "$field" ]; then
                printf '%s|%s' "$field" "$path"
                return 0
            fi
        fi
    done <<< "$ops"
    return 0
}

# ── main decision ────────────────────────────────────────────────────────────

# Reads PreToolUse JSON on stdin. On stdout: "<field>|<file>" if a blocking
# mutation is detected; nothing otherwise. Never itself exits non-zero.
decide() {
    local input tool_name file
    input="$(cat)" || return 0
    [ -z "$input" ] && return 0

    tool_name="$(printf '%s' "$input" | command jq -r '.tool_name // empty' 2>/dev/null)" || return 0
    case "$tool_name" in
        Edit|Write|MultiEdit) : ;;
        # The lean-ctx write surface — direct, or proxied through ctx_call.
        # decide_ctx_patch re-checks the EFFECTIVE tool name, so a ctx_call
        # naming some other inner tool falls out there.
        mcp__lean-ctx__ctx_patch|ctx_patch|mcp__lean-ctx__ctx_call|ctx_call)
            decide_ctx_patch "$input"
            return 0
            ;;
        *) return 0 ;;
    esac

    file="$(printf '%s' "$input" | command jq -r '.tool_input.file_path // empty' 2>/dev/null)" || return 0
    [ -z "$file" ] && return 0
    is_scoped "$file" || return 0

    # SCAFFOLDING EXEMPTION: target does not exist yet -> initial authoring,
    # nothing to protect. Uniform for Write, Edit, and MultiEdit (see header).
    [ -f "$file" ] || return 0

    case "$tool_name" in
        Edit)
            # (file existence already guaranteed by the uniform exemption above)
            local old new existing simulated old_fm new_fm field
            old="$(printf '%s' "$input" | command jq -r '.tool_input.old_string // empty' 2>/dev/null)" || return 0
            new="$(printf '%s' "$input" | command jq -r '.tool_input.new_string // empty' 2>/dev/null)" || return 0
            # A real Edit always carries old_string; a payload without one
            # cannot be simulated and is not a write this guard can judge.
            [ -z "$old" ] && return 0
            existing="$(cat "$file" 2>/dev/null)" || return 0
            case "$existing" in
                *"$old"*) : ;;
                *) return 0 ;;   # old_string absent -> the real Edit would fail -> nothing to protect
            esac
            simulated="${existing/"$old"/"$new"}"
            old_fm="$(extract_frontmatter "$existing")"
            new_fm="$(extract_frontmatter "$simulated")"
            field="$(changed_field "$old_fm" "$new_fm")" || return 0
            [ -n "$field" ] && printf '%s|%s' "$field" "$file"
            ;;
        MultiEdit)
            # Cumulative simulation: apply each edit, in payload order, to a
            # running copy of the real file content. If any edit's old_string
            # doesn't match at that point in the chain, the real MultiEdit
            # call would fail atomically (nothing lands on disk) -> ALLOW the
            # whole call rather than judging the remaining edits.
            local edits existing content old new replace_all entry old_fm new_fm field matched
            existing="$(cat "$file" 2>/dev/null)" || return 0
            edits="$(printf '%s' "$input" | command jq -c '.tool_input.edits // [] | .[]' 2>/dev/null)" || return 0
            # No edits array — nothing to simulate; see the Edit branch.
            [ -z "$edits" ] && return 0
            content="$existing"
            matched=1
            while IFS= read -r entry; do
                [ -z "$entry" ] && continue
                old="$(printf '%s' "$entry" | command jq -r '.old_string // empty' 2>/dev/null)" || return 0
                new="$(printf '%s' "$entry" | command jq -r '.new_string // empty' 2>/dev/null)" || return 0
                replace_all="$(printf '%s' "$entry" | command jq -r '.replace_all // false' 2>/dev/null)" || return 0
                case "$content" in
                    *"$old"*) : ;;
                    *) matched=0; break ;;
                esac
                if [ "$replace_all" = "true" ]; then
                    content="${content//"$old"/"$new"}"
                else
                    content="${content/"$old"/"$new"}"
                fi
            done <<< "$edits"
            [ "$matched" -eq 0 ] && return 0
            old_fm="$(extract_frontmatter "$existing")"
            new_fm="$(extract_frontmatter "$content")"
            field="$(changed_field "$old_fm" "$new_fm")" || return 0
            [ -n "$field" ] && printf '%s|%s' "$field" "$file"
            ;;
        Write)
            # (file existence already guaranteed by the uniform exemption above)
            local existing content old_fm new_fm field
            existing="$(cat "$file" 2>/dev/null)" || return 0
            content="$(printf '%s' "$input" | command jq -r '.tool_input.content // empty' 2>/dev/null)" || return 0
            old_fm="$(extract_frontmatter "$existing")"
            new_fm="$(extract_frontmatter "$content")"
            field="$(changed_field "$old_fm" "$new_fm")" || return 0
            [ -n "$field" ] && printf '%s|%s' "$field" "$file"
            ;;
    esac
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────

self_test() {
    local p=0 f=0
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }

    echo "=== goalforge-single-writer.sh --self-test ==="

    local d
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' RETURN

    # Fixtures live in a throwaway git repo under the trap-cleaned tmpdir —
    # its plans/ tree satisfies the git-root branch of is_scoped() without
    # touching any real plan file. Existing file for the block cases (the
    # scaffolding exemption would otherwise short-circuit them); a
    # nonexistent sibling path for the exemption cases.
    git init -q "$d/repo" 2>/dev/null
    mkdir -p "$d/repo/plans/feat/wp-01"
    local plans_file="$d/repo/plans/feat/wp-01/overview.md"
    local new_plans_file="$d/repo/plans/feat/wp-02/overview.md"
    mkdir -p "$d/repo/plans/feat/wp-02"
    printf -- '---\ntitle: Old Title\nstatus: hardened\ngoal_approved_version: 1\n---\nbody\n' > "$plans_file"
    local nonplans_file="$d/overview.md"
    printf -- '---\nstatus: hardened\n---\n' > "$nonplans_file"
    local body_status_file="$d/repo/plans/feat/wp-01/spec.md"
    printf -- '---\ntitle: Body Test\nstatus: hardened\n---\nCheckpoint notes:\nstatus: something\n' > "$body_status_file"

    # 1) Edit mutating existing status: in a plans path -> exit 2
    local payload out rc
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: hardened\n", new_string:"status: ready\n"}}')"
    out="$(printf '%s' "$payload" | decide)"; rc=$?
    [ -n "$out" ] && [[ "$out" == status\|* ]] && ok "Edit status mutation in plans path -> detected" \
        || no "Edit status mutation in plans path -> got '$out' rc=$rc"

    # 2) Edit on non-plans path -> 0 (nothing detected)
    payload="$(command jq -n --arg fp "$nonplans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: hardened\n", new_string:"status: ready\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -z "$out" ] && ok "Edit on non-plans path -> not detected" || no "Edit on non-plans path -> got '$out'"

    # 3) Edit changing title: only -> 0
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"title: Old Title\n", new_string:"title: New Title\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -z "$out" ] && ok "Edit changing title only -> not detected" || no "Edit changing title only -> got '$out'"

    # 4) non-Edit tool_name (Bash) -> 0
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"Bash", tool_input:{command:"echo status: ready"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -z "$out" ] && ok "Bash tool_name -> not detected" || no "Bash tool_name -> got '$out'"

    # 5) goal_approved_version: mutation -> 2
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"goal_approved_version: 1\n", new_string:"goal_approved_version: 2\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == goal_approved_version\|* ]] && ok "goal_approved_version mutation -> detected" \
        || no "goal_approved_version mutation -> got '$out'"

    # 6) MultiEdit batch with one offending edit -> 2 (old_strings must be
    #    real substrings of $plans_file's actual content — simulate-and-
    #    compare checks the real file, not the snippets in isolation)
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
            {old_string:"title: Old Title\n", new_string:"title: New Title\n"},
            {old_string:"status: hardened\n", new_string:"status: ready\n"}
        ]}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == status\|* ]] && ok "MultiEdit batch with one offending edit -> detected" \
        || no "MultiEdit batch with one offending edit -> got '$out'"

    # 6b) MultiEdit bypass demonstration: neither snippet contains a
    #     "status:" key by itself, yet the substitution still lands on the
    #     status: line once applied to the real file -> must still detect.
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
            {old_string:"title: Old Title\n", new_string:"title: New Title\n"},
            {old_string:"hardened", new_string:"ready"}
        ]}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == status\|* ]] && ok "MultiEdit second-edit bare-value bypass -> detected" \
        || no "MultiEdit second-edit bare-value bypass -> got '$out'"

    # 6c) Bare-value bypass demonstration (single Edit): neither snippet
    #     contains a "status:" key, only the value tokens — the old
    #     snippet-diffing logic ALLOWed this; simulate-and-compare must BLOCK
    #     because the substitution still lands on the frontmatter status:
    #     line in the real file.
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"hardened", new_string:"ready"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == status\|* ]] && ok "Edit bare-value bypass (no 'status:' in either snippet) -> detected" \
        || no "Edit bare-value bypass -> got '$out'"

    # 6d) Partial-key bypass demonstration: old/new snippets are missing the
    #     leading "st" of "status:" — must still BLOCK since the real
    #     substitution reconstitutes "status:" on disk.
    payload="$(command jq -n --arg fp "$plans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"atus: hardened", new_string:"atus: ready"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == status\|* ]] && ok "Edit partial-key bypass ('atus:' snippet) -> detected" \
        || no "Edit partial-key bypass -> got '$out'"

    # 6e) False-positive guard: a BODY line that happens to start with
    #     "status:" (prose/checkpoint text below the closing frontmatter
    #     fence) must NOT trip the guard — only the frontmatter region is in
    #     scope.
    payload="$(command jq -n --arg fp "$body_status_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: something\n", new_string:"status: else\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -z "$out" ] && ok "Edit on body 'status:' line (not frontmatter) -> not detected" \
        || no "Edit on body 'status:' line -> got '$out'"

    # 7) Scaffolding: Write to a NONEXISTENT plans path with status: content -> allow
    payload="$(command jq -n --arg fp "$new_plans_file" \
        '{tool_name:"Write", tool_input:{file_path:$fp, content:"---\nstatus: draft\n---\nbody\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -z "$out" ] && ok "Write to nonexistent plans path (scaffolding) -> allowed" \
        || no "Write to nonexistent plans path -> got '$out'"

    # 7b) Scaffolding exemption is uniform: Edit against a nonexistent file -> allow
    payload="$(command jq -n --arg fp "$new_plans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: draft\n", new_string:"status: ready\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -z "$out" ] && ok "Edit on nonexistent plans file -> allowed (uniform exemption)" \
        || no "Edit on nonexistent plans file -> got '$out'"

    # 8) Create-then-edit is NOT exempt: once the file exists, a status:
    #    mutation via Edit blocks (exists-check runs fresh at call time).
    printf -- '---\nstatus: draft\n---\nbody\n' > "$new_plans_file"
    payload="$(command jq -n --arg fp "$new_plans_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: draft\n", new_string:"status: ready\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == status\|* ]] && ok "Edit status on just-created file -> detected (no exemption)" \
        || no "Edit status on just-created file -> got '$out'"

    # 10) PLANS_ROOT resolution pair (spec §Interface Contract). A REAL status
    #     mutation (old/new snippets that actually occur in the fixture) under
    #     $SDD_PLANS_DIR blocks with exit 2; the same payload outside every
    #     resolved root takes the silent exit-0 fast path. Driven through a
    #     SUBPROCESS so the assertion covers the real entry point (stdin, helper
    #     sourcing and exit code included), not just decide() — and asserting
    #     exit 2 makes it a check of the SCOPING and the GUARD together, which a
    #     payload the hook merely fails to evaluate could never be.
    mkdir -p "$d/sdd/plans/f" "$d/sdd/elsewhere"
    printf -- '---\nstatus: draft\n---\n' > "$d/sdd/plans/f/overview.md"
    printf -- '---\nstatus: draft\n---\n' > "$d/sdd/elsewhere/overview.md"
    mutation() { # <overview path> — a status: draft -> verified Edit payload
        command jq -n --arg fp "$1" \
            '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: draft", new_string:"status: verified"}}'
    }
    local pos_out neg_out pos_rc neg_rc
    pos_out="$(mutation "$d/sdd/plans/f/overview.md" | SDD_PLANS_DIR="$d/sdd/plans" bash "$SELF" 2>&1)"; pos_rc=$?
    { [ "$pos_rc" = 2 ] && [ -n "$pos_out" ]; } \
        && ok "status mutation under \$SDD_PLANS_DIR -> exit 2 with a reason" \
        || no "under \$SDD_PLANS_DIR should block (rc=$pos_rc, out='$pos_out')"

    neg_out="$(mutation "$d/sdd/elsewhere/overview.md" | SDD_PLANS_DIR="$d/sdd/plans" bash "$SELF" 2>&1)"; neg_rc=$?
    { [ "$neg_rc" = 0 ] && [ -z "$neg_out" ]; } \
        && ok "same mutation outside every plans root -> silent exit-0 fast path" \
        || no "outside every plans root should fast-path silently (rc=$neg_rc, out='$neg_out')"

    # 11) PLANS_ROOT legs 2 and 3 (spec §Interface Contract). SDD_PLANS_DIR is
    #     UNSET for all four and $HOME points at an empty sandbox, so each case
    #     can only pass through the leg it names: deleting the git-root leg or
    #     the ~/.claude/plans leg from goalforge-plans-root.sh turns one of
    #     these red.
    local hs="$d/home" lf
    mkdir -p "$hs/.claude/plans/f" "$hs/.claude/notplans"
    git init -q "$d/leg2repo" 2>/dev/null
    mkdir -p "$d/leg2repo/plans/f" "$d/leg2repo/notplans"
    # Leg 2b shape: plans/ is its OWN git repo nested in the outer one. The git
    # root of a file below it is the plans dir itself, so leg 2 alone resolves
    # to `plans/plans` and the file falls out of scope. This is the real-world
    # layout of a private plans repo gitignored by a public parent.
    git init -q "$d/leg2brepo" 2>/dev/null
    mkdir -p "$d/leg2brepo/plans/f"
    git init -q "$d/leg2brepo/plans" 2>/dev/null
    for lf in "$d/leg2repo/plans/f" "$d/leg2repo/notplans" "$d/leg2brepo/plans/f" "$hs/.claude/plans/f" "$hs/.claude/notplans"; do
        printf -- '---\nstatus: draft\n---\n' > "$lf/overview.md"
    done
    leg() { # <label> <overview path> <block|silent>
        local out rc
        out="$(mutation "$2" | env -u SDD_PLANS_DIR HOME="$hs" bash "$SELF" 2>&1)"; rc=$?
        if [ "$3" = block ]; then
            { [ "$rc" = 2 ] && [ -n "$out" ]; } && ok "$1" || no "$1 (rc=$rc, out='$out')"
        else
            { [ "$rc" = 0 ] && [ -z "$out" ]; } && ok "$1" || no "$1 (rc=$rc, out='$out')"
        fi
    }
    leg "leg 2: <git-root>/plans/** -> exit 2"                     "$d/leg2repo/plans/f/overview.md"   block
    leg "leg 2 negative: same git repo outside plans/ -> silent"   "$d/leg2repo/notplans/overview.md"  silent
    leg "leg 2b: plans/ is its OWN git repo -> exit 2"             "$d/leg2brepo/plans/f/overview.md"  block
    leg "leg 3: \$HOME/.claude/plans/** -> exit 2"                 "$hs/.claude/plans/f/overview.md"   block
    leg "leg 3 negative: \$HOME/.claude outside plans/ -> silent"  "$hs/.claude/notplans/overview.md"  silent

    # 12) human_required (ticket-72 monotonicity): null -> "<reason>" ALLOWED.
    mkdir -p "$d/repo/plans/feat/wp-hr"
    local hr_file="$d/repo/plans/feat/wp-hr/overview.md"
    printf -- '---\ntitle: HR Test\nhuman_required: null\n---\nbody\n' > "$hr_file"
    payload="$(command jq -n --arg fp "$hr_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"human_required: null\n", new_string:"human_required: \"schema migration\"\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -z "$out" ] && ok "human_required null -> \"<reason>\" (SET) -> allowed" \
        || no "human_required null -> reason should be allowed, got '$out'"

    # 12b) human_required: an already-set reason -> a DIFFERENT reason -> BLOCKED.
    printf -- '---\ntitle: HR Test 2\nhuman_required: "old reason"\n---\nbody\n' > "$hr_file"
    payload="$(command jq -n --arg fp "$hr_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"human_required: \"old reason\"\n", new_string:"human_required: \"new reason\"\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == human_required\|* ]] && ok "human_required set -> different reason (weaken) -> blocked" \
        || no "human_required set -> different reason should block, got '$out'"

    # 12c) human_required: set -> null (CLEAR) -> BLOCKED.
    printf -- '---\ntitle: HR Test 3\nhuman_required: "some reason"\n---\nbody\n' > "$hr_file"
    payload="$(command jq -n --arg fp "$hr_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"human_required: \"some reason\"\n", new_string:"human_required: null\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == human_required\|* ]] && ok "human_required set -> null (clear) -> blocked" \
        || no "human_required set -> null should block, got '$out'"

    # 12d) human_required: field REMOVED entirely -> BLOCKED.
    printf -- '---\ntitle: HR Test 4\nhuman_required: "some reason"\nother: x\n---\nbody\n' > "$hr_file"
    payload="$(command jq -n --arg fp "$hr_file" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"human_required: \"some reason\"\nother: x\n", new_string:"other: x\n"}}')"
    out="$(printf '%s' "$payload" | decide)"
    [ -n "$out" ] && [[ "$out" == human_required\|* ]] && ok "human_required field removed -> blocked" \
        || no "human_required field removal should block, got '$out'"

    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

# ── entry point ──────────────────────────────────────────────────────────────

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

main() {
    command -v jq >/dev/null 2>&1 || { cat >/dev/null; exit 0; }

    local result field file tool_name
    result="$(decide)" || exit 0
    [ -z "$result" ] && exit 0

    field="${result%%|*}"
    file="${result#*|}"
    if [ "$field" = "human_required" ]; then
        echo "goalforge-single-writer: mutation of 'human_required:' in ${file} is blocked — human_required is monotonic (ticket-72): an agent may SET it once (null -> \"<reason>\") and may never clear or weaken it." >&2
    else
        echo "goalforge-single-writer: direct mutation of '${field}:' in ${file} is blocked — use the sanctioned writers goalforge-transition.sh / goalforge-goal-hash.sh (Bash path)." >&2
    fi
    goalforge_emit_gate_result "single-writer" "fail" "direct mutation of '${field}:'" "$file"
    exit 2
}

main
