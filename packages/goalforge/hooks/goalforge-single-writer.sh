#!/usr/bin/env bash
# goalforge-single-writer.sh — PreToolUse hard guard: block direct tool-surface
# mutation of the `status:`/`goal_approved_version:` frontmatter fields on
# plan/WP files. Single-writer enforcement for those two fields.
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
# DIVISION OF LABOR: hooks/goalforge-transition-guard.sh is a separate, NOT-wired
# ADVISORY guard over edge *legality* (is old-status -> new-status a valid SDD
# transition). THIS hook owns hard field-mutation protection — it does not
# care whether the transition is legal, only whether the write is coming
# through a tool surface instead of the sanctioned Bash-path writers.
#
# SCOPE: <git-root>/plans/** or ~/.claude/plans/** (dual-root — do not
# hardcode $HOME/.claude/plans as the only root; that was the precedent bug
# in goalforge-frontmatter-touch.sh), basename overview.md, spec.md,
# task-*.md, or brief-task-*.md (briefs are write-once — see BRIEF
# IMMUTABILITY in decide()).
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
# ZERO-BREAKAGE: any internal error (malformed JSON, missing jq, unreadable
# file) exits 0 — this hook must never block because it broke internally.
# The ONLY non-zero exit is exit 2 for a confirmed direct mutation of
# status:/goal_approved_version: on an in-scope file.
#
# Usage:
#   <PreToolUse JSON on stdin> | goalforge-single-writer.sh
#   goalforge-single-writer.sh --self-test
set -uo pipefail

FIELDS="status goal_approved_version"

# ── path scoping ─────────────────────────────────────────────────────────────

# True (0) iff $1 is $2 or a path under $2.
path_in_root() {
    case "$1" in
        "$2"|"$2"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# True (0) iff $1's basename is a protected plan/WP file AND $1 resolves under
# either plans root (git-root plans/ first, else ~/.claude/plans/).
is_scoped() {
    local fp="$1" bn gitroot
    [ -n "$fp" ] || return 1
    bn="$(basename -- "$fp")"
    case "$bn" in
        overview.md|spec.md|task-*.md|brief-task-*.md) : ;;
        *) return 1 ;;
    esac
    gitroot="$(git -C "$(dirname -- "$fp")" rev-parse --show-toplevel 2>/dev/null)" || gitroot=""
    if [ -n "$gitroot" ] && path_in_root "$fp" "$gitroot/plans"; then
        return 0
    fi
    path_in_root "$fp" "$HOME/.claude/plans"
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

# Exit 0 (true) iff $field appears in $old with a value, and its value in
# $new differs (including "absent in new" = differs).
field_changed() {
    local old="$1" new="$2" field="$3" oldval newval
    oldval="$(extract_value "$old" "$field")"
    [ -z "$oldval" ] && return 1        # field not present in old -> N/A
    newval="$(extract_value "$new" "$field")"
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
        *) return 0 ;;
    esac

    file="$(printf '%s' "$input" | command jq -r '.tool_input.file_path // empty' 2>/dev/null)" || return 0
    [ -z "$file" ] && return 0
    is_scoped "$file" || return 0

    # SCAFFOLDING EXEMPTION: target does not exist yet -> initial authoring,
    # nothing to protect. Uniform for Write, Edit, and MultiEdit (see header).
    [ -f "$file" ] || return 0

    # BRIEF IMMUTABILITY (wp-06 follow-up, wp-08 scope): brief-task-*.md is
    # write-once — delta-only immutable once authored. ANY Edit/Write/
    # MultiEdit on an existing brief blocks regardless of which lines it
    # touches (briefs carry no status: field, so field-diffing would never
    # fire). Re-authoring a stale brief goes through goalforge-execute's
    # sanctioned Bash-path staleness flow; creation stays exempt above.
    case "$(basename -- "$file")" in
        brief-task-*.md) printf '%s|%s' "brief-immutable" "$file"; return 0 ;;
    esac

    case "$tool_name" in
        Edit)
            # (file existence already guaranteed by the uniform exemption above)
            local old new existing simulated old_fm new_fm field
            old="$(printf '%s' "$input" | command jq -r '.tool_input.old_string // empty' 2>/dev/null)" || return 0
            new="$(printf '%s' "$input" | command jq -r '.tool_input.new_string // empty' 2>/dev/null)" || return 0
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
    local new_plans_file="$d/repo/plans/feat/wp-02/task-01-fresh.md"
    mkdir -p "$d/repo/plans/feat/wp-02"
    printf -- '---\ntitle: Old Title\nstatus: hardened\ngoal_approved_version: 1\n---\nbody\n' > "$plans_file"
    local nonplans_file="$d/overview.md"
    printf -- '---\nstatus: hardened\n---\n' > "$nonplans_file"
    local body_status_file="$d/repo/plans/feat/wp-01/task-99-body.md"
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
    if [ "$field" = "brief-immutable" ]; then
        echo "goalforge-single-writer: ${file} is an immutable brief (write-once) — never Edit/Write an existing brief-task-*.md; a stale brief is re-authored via goalforge-execute's sanctioned Bash-path staleness flow." >&2
        exit 2
    fi
    echo "goalforge-single-writer: direct mutation of '${field}:' in ${file} is blocked — use the sanctioned writers goalforge-transition.sh / goalforge-goal-hash.sh (Bash path)." >&2
    exit 2
}

main
