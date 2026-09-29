#!/usr/bin/env bash
# goalforge-preharden-lint.sh — deterministic pre-harden lint for one WP dir.
#
# Catches, BEFORE a harden panel spends tokens on them, the two defect classes
# the goalforge harden panels repeatedly re-found across old WPs
# (improvement-report process note, 2026-07-19):
#
#   P1  plugin-anchored paths in planning docs ($COGWRIGHT_ROOT,
#       $CLAUDE_PLUGIN_ROOT, plugins/cogwright literals) — the local tree is
#       authoritative (wp-13), plugin paths are stale anchors.
#   V1  `|| true` no-op inside a task verify: block — the check can never fail.
#   V2  self-referential verify — the verify: block greps/reads only the WP's
#       own planning docs (overview.md / task-*.md / findings.md), proving the
#       words exist, not the work.
#   V3  no executable check — verify: block contains only echo/printf/comments.
#   V4  sole `--help` probe — the only command is a `--help` invocation.
#   V5  WP-altitude `goal.verification.command` not command-shaped (prose, a
#       bare boolean, echo-only, a sole `--help` probe, or an em-dash
#       narrative clause) — ticket-73/spec.md C3 G2. ERROR (exit 2) on
#       `schema_version: 6` (the C1/C2 slim shape); WARN-only on
#       `schema_version: 5` (ratchet: baseline compat, never promoted to
#       ERROR — migrated when a WP is next touched); absent schema_version
#       (pre-v4 legacy) is exempt entirely. A schema-6 WP's overview.md is
#       also run through `goalforge-section-lint.sh` (C1 8-section shape)
#       here — a failure there is a V5 ERROR too.
#   V6  a schema-6 `goal.verification.behaviors[]` row whose
#       `given:`/`when:`/`then:`/`oracle:` text pins the check to a live corpus
#       root (`$HOME`, `~/.claude`, `~/`, `CLAUDE_CONFIG_DIR`, `/home/`) while
#       naming no shipped fixture root. Exemption tokens (case-insensitive):
#       `fixtures/`, the bare word `fixtures`, `hermetic`, `fixture root`.
#       HEURISTIC, WARN-only, never ERROR. A WP with no behaviors[] (schema 5,
#       pre-v4) is skipped.
#
#       Parser limits: behavior values are read as plain inline scalars only.
#       A block-scalar (`>` / `|`) or flow-style value is NOT parsed — its
#       continuation lines are invisible to V6, so such a row degrades to a
#       MISSED check (no WARN), never a spurious one.
#
#       (A prior keyword check — "oracle names no known-bad case", grepping for
#       `known-bad`/`exit 2`/`sabotage`/… — was removed: a keyword grep on prose
#       is not evidence a known-bad input exists. Measured on the live corpus it
#       flagged 7 of 11 rows, several of them compliant.)
#   V7  static revision check: every `git` command in a task `verify:` block is
#       parsed (whitespace split, no shell evaluation) for revision tokens —
#       every operand of `git rev-parse`, plus sha-shaped, HEAD-shaped and
#       `a..b` / `a...b` operands of any other git subcommand. Each token is
#       resolved by a fixed read-only `git rev-parse --verify --quiet
#       <tok>^{commit}` that this lint invokes itself (argv, no shell, no author
#       text interpolated into a shell string) inside the WP's own repository. An
#       unresolvable token is an ERROR. NO part of a verify block is ever run.
#       Every block prints an INFO line saying how many tokens were checked and
#       that the gate did not run; a token it cannot check statically (shell
#       expansion, `rev:path`, glob) and a WP with no verify blocks (schema-6 WPs
#       carry none) print INFO too, so "passed" and "never ran" read differently.
#   PI  path-idiom findings: goalforge-path-idiom-lint.sh is run over the WP dir
#       (OQ5 wiring). Each finding is relayed as `WARN [PIn] <file>:<line>: ...`
#       (WARN channel, exit 1, as the path-idiom lint's own exit 1); an
#       unreadable input (its exit 2) is `ERROR [PI]`.
#   V8  resolve the referent: every `<placeholder>`-shaped token in
#       `goal.constraints` must name a populated top-level frontmatter field of
#       the WP, and every backticked file-shaped token (contains `/` or ends in
#       .md/.sh/.py/.json/.yaml/.yml/.txt/.toml) must exist under the WP dir or
#       one of its ancestors. An unresolved token is an ERROR.
#
# Usage: goalforge-preharden-lint.sh <wp-dir> | --self-test
# Exit: 0 clean; 1 findings (WARN lines on stdout, gate-consumable);
#       2 usage/internal error, OR an ERROR — V5 (schema-6 command-shape or
#       section-lint failure), V7 (a verify block naming an unresolvable
#       revision), V8 (an unresolved placeholder or missing named artifact) or
#       PI (an input the path-idiom lint could not read); fail-closed, distinct
#       from the WARN channel.
# Offline, deterministic, read-only, no LLM. Executes no text taken from a WP: its
# only subprocesses are fixed argv invocations (python3 frontmatter parsers,
# sibling lints, `git rev-parse --verify --quiet`). sdd-* diagnostic prefix per
# CLI-surface freeze.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn_count=0
warn() { echo "WARN [$1] $2"; warn_count=$((warn_count+1)); }

err_count=0
err() { echo "ERROR [$1] $2"; err_count=$((err_count+1)); }

# Print the verify: block scalar body of a task file (indented lines after
# `verify: |`), stripped of the two-space indent.
verify_block() {
    awk '
        /^verify: \|/ { grab=1; next }
        grab && /^[a-z_]+:/ { grab=0 }
        grab && /^---$/ { grab=0 }
        grab { sub(/^  /, ""); print }
    ' "$1"
}

# V5 helper — extracts the WP's top-level `schema_version:` and the nested
# `goal.verification.command` scalar (fixed 0/2/4-space frontmatter indent
# per schema.md's `goal:` block). Prints SCHEMA:/PRESENT:/COMMAND: lines.
# Exit 1 on unreadable file or missing/unterminated frontmatter.
extract_verification() {
    python3 - "$1" <<'PY'
import sys, re
path = sys.argv[1]
try:
    text = open(path, encoding='utf-8').read()
except OSError:
    sys.exit(1)
lines = text.split('\n')
if not lines or lines[0].strip() != '---':
    sys.exit(1)
end = None
for i in range(1, len(lines)):
    if lines[i].strip() == '---':
        end = i
        break
if end is None:
    sys.exit(1)
fm = lines[1:end]

def top_value(key):
    pat = re.compile(r'^' + re.escape(key) + r':\s*(.*)$')
    for ln in fm:
        m = pat.match(ln)
        if m:
            return m.group(1).strip()
    return None

schema = top_value('schema_version') or ''

command = None
present = False
in_goal = in_ver = False
for ln in fm:
    if re.match(r'^goal:\s*$', ln):
        in_goal, in_ver = True, False
        continue
    if in_goal and re.match(r'^[A-Za-z_]', ln):
        in_goal = in_ver = False
    if in_goal and re.match(r'^  verification:\s*$', ln):
        in_ver = True
        continue
    if in_goal and in_ver and re.match(r'^  [A-Za-z_]', ln) and not re.match(r'^  verification:', ln):
        in_ver = False
    if in_goal and in_ver:
        m = re.match(r'^    command:\s*(.*)$', ln)
        if m:
            present = True
            val = m.group(1).strip()
            if len(val) >= 2 and val[0] == val[-1] == '"':
                val = val[1:-1]
            command = val
            break

print(f"SCHEMA:{schema}")
print(f"PRESENT:{1 if present else 0}")
print(f"COMMAND:{command if command is not None else ''}")
PY
}

# V5 helper — is `$1` command-shaped (one aggregate entrypoint, no smuggled
# prose)? Sets CMDLINT_REASON and returns 1 on: empty, a bare boolean
# literal, an em-dash narrative clause, a first token that is neither a
# known executable nor path-like, echo/printf-only, or a sole `--help` probe.
CMDLINT_REASON=""
command_shaped() {
    local s first
    CMDLINT_REASON=""
    s="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -z "$s" ]; then CMDLINT_REASON="empty command"; return 1; fi
    case "$s" in
        true|false) CMDLINT_REASON="boolean literal '$s', not an executable command"; return 1 ;;
    esac
    if printf '%s' "$s" | grep -q '—'; then
        CMDLINT_REASON="em-dash narrative clause, not a command"
        return 1
    fi
    first="$(printf '%s' "$s" | awk '{print $1}')"
    case "$first" in
        bash|sh|zsh|python|python3|node|bun|npm|npx|yarn|make|pytest|go|cargo|deno|tsc|jest|vitest|uv|poetry|cmake|ctest|./*|../*|/*) ;;
        *)
            if ! printf '%s' "$first" | grep -q '/'; then
                CMDLINT_REASON="first token '$first' is not command-shaped (prose?)"
                return 1
            fi
            ;;
    esac
    local echo_only=1 seg
    IFS='&;' read -ra _segs <<< "$s"
    for seg in "${_segs[@]:-}"; do
        seg="$(printf '%s' "$seg" | sed 's/^[[:space:]]*//')"
        [ -z "$seg" ] && continue
        printf '%s' "$seg" | grep -qE '^(echo|printf)\b' || { echo_only=0; break; }
    done
    if [ "$echo_only" -eq 1 ]; then
        CMDLINT_REASON="echo/printf only — no executable check"
        return 1
    fi
    if printf '%s' "$s" | grep -qE -- '--help' && [ "$(printf '%s' "$s" | wc -w)" -le 3 ]; then
        CMDLINT_REASON="bare --help probe"
        return 1
    fi
    return 0
}

# V6 helper — emits one TAB-separated row per
# `goal.verification.behaviors[]` entry of a WP overview.md:
#   <id> TAB <given+when+then+oracle text>
# Same frontmatter/indent assumptions as extract_verification (schema.md's
# `goal:` block); reuses the python3 path that helper already depends on, so
# no new interpreter dependency is introduced. Prints nothing when the WP has
# no behaviors[] (schema-5 and pre-v4 WPs).
extract_behaviors() {
    python3 - "$1" <<'PY'
import sys, re
try:
    text = open(sys.argv[1], encoding='utf-8').read()
except OSError:
    sys.exit(0)
lines = text.split('\n')
if not lines or lines[0].strip() != '---':
    sys.exit(0)
end = None
for i in range(1, len(lines)):
    if lines[i].strip() == '---':
        end = i
        break
if end is None:
    sys.exit(0)
fm = lines[1:end]

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
        v = v[1:-1]
    return v

rows, cur = [], None
in_goal = in_ver = in_beh = False
for ln in fm:
    if re.match(r'^goal:\s*$', ln):
        in_goal, in_ver, in_beh = True, False, False
        continue
    if in_goal and re.match(r'^[A-Za-z_]', ln):
        in_goal = in_ver = in_beh = False
    if not in_goal:
        continue
    if re.match(r'^  verification:\s*$', ln):
        in_ver, in_beh = True, False
        continue
    if in_ver and re.match(r'^  [A-Za-z_]', ln):
        in_ver = in_beh = False
        continue
    if not in_ver:
        continue
    if re.match(r'^    behaviors:\s*(\[\s*\])?\s*$', ln):
        in_beh = True
        continue
    if in_beh and re.match(r'^    [A-Za-z_]', ln):
        in_beh = False
        continue
    if not in_beh:
        continue
    m = re.match(r'^      - (\w+):\s*(.*)$', ln)
    if m:
        cur = {'id': '', 'given': '', 'when': '', 'then': '', 'oracle': ''}
        rows.append(cur)
        cur[m.group(1)] = unquote(m.group(2))
        continue
    m = re.match(r'^        (\w+):\s*(.*)$', ln)
    if m and cur is not None:
        cur[m.group(1)] = unquote(m.group(2))

def flat(*parts):
    return re.sub(r'\s+', ' ', ' '.join(parts)).strip()

for r in rows:
    bid = r.get('id') or '<unnamed>'
    print('\t'.join([
        bid,
        flat(r.get('given', ''), r.get('when', ''), r.get('then', ''), r.get('oracle', '')),
    ]))
PY
}

# V6 token lists — literal, case-insensitive, heuristic (see header).
V6_LIVE_ROOTS='[$]HOME|~/[.]claude|~/|CLAUDE_CONFIG_DIR|/home/'
V6_FIXTURE_TOKENS='fixtures/|\bfixtures\b|hermetic|fixture root'

# V6 — heuristic live-corpus-root lint. WARN channel only, never ERROR.
lint_wp_behaviors() {
    local wp="$1" ov="$wp/overview.md" base rows bid atext
    [ -f "$ov" ] || return 0
    base="$(basename -- "$wp")"
    rows="$(extract_behaviors "$ov")"
    [ -n "$rows" ] || return 0
    while IFS="$(printf '\t')" read -r bid atext; do
        [ -n "${bid:-}" ] || continue
        if printf '%s' "$atext" | grep -qE "$V6_LIVE_ROOTS" \
           && ! printf '%s' "$atext" | grep -qiE "$V6_FIXTURE_TOKENS"; then
            warn V6 "$base: $bid: oracle resolves against a live corpus root with no shipped fixture root"
        fi
    done <<EOF
$rows
EOF
}

# V5 — WP-altitude verification.command shape + C1 section lint.
lint_wp_verification() {
    local wp="$1" ov="$wp/overview.md" base info schema present command
    [ -f "$ov" ] || return 0
    base="$(basename -- "$wp")"

    info="$(extract_verification "$ov")" || {
        err V5 "$base: overview.md unreadable or missing/unterminated frontmatter"
        return 0
    }
    schema="$(printf '%s\n' "$info" | sed -n 's/^SCHEMA://p')"
    present="$(printf '%s\n' "$info" | sed -n 's/^PRESENT://p')"
    command="$(printf '%s\n' "$info" | sed -n 's/^COMMAND://p')"

    case "$schema" in
        6)
            if [ "$present" != "1" ]; then
                err V5 "$base: schema_version 6 requires goal.verification.command"
            elif ! command_shaped "$command"; then
                err V5 "$base: goal.verification.command not command-shaped — $CMDLINT_REASON"
            fi
            local sl_out
            if ! sl_out="$("$SCRIPT_DIR/goalforge-section-lint.sh" "$ov" 2>&1)"; then
                err V5 "$base: section-lint — ${sl_out##*: }"
            fi
            ;;
        5)
            if [ "$present" = "1" ] && ! command_shaped "$command"; then
                warn V5 "$base: schema_version 5 baseline — goal.verification.command not command-shaped — $CMDLINT_REASON"
            fi
            ;;
        *) : ;;   # absent schema_version — pre-v4 legacy, exempt
    esac
}

# V8 helper — prints the WP overview's goal.verification.strategy (STRATEGY:)
# and one CONSTRAINT: line per goal.constraints entry (flow or block list), and
# one FIELD:<key>=<value> line per top-level frontmatter scalar.
extract_goal_refs() {
    python3 - "$1" <<'PY'
import sys, re
try:
    lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
except OSError:
    sys.exit(0)
if not lines or lines[0].strip() != '---':
    sys.exit(0)
end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None)
if end is None:
    sys.exit(0)
fm = lines[1:end]

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
        v = v[1:-1]
    return v

for ln in fm:
    m = re.match(r'^([A-Za-z_][\w-]*):\s*(.*)$', ln)
    if m:
        val = unquote(re.sub(r'\s+#.*$', '', m.group(2)))
        print("FIELD:" + m.group(1) + "=" + val)

in_goal = in_ver = in_con = False
for ln in fm:
    if re.match(r'^goal:\s*$', ln):
        in_goal = True
        continue
    if in_goal and re.match(r'^[A-Za-z_]', ln):
        in_goal = in_ver = in_con = False
    if not in_goal:
        continue
    if re.match(r'^  [A-Za-z_]', ln):
        in_ver = bool(re.match(r'^  verification:\s*$', ln))
        in_con = False
        m = re.match(r'^  constraints:\s*(.*)$', ln)
        if m:
            val = m.group(1).strip()
            if val.startswith('['):
                for item in re.findall(r'"((?:[^"\\]|\\.)*)"|\'([^\']*)\'', val):
                    print("CONSTRAINT:" + (item[0] or item[1]))
            else:
                in_con = True
        continue
    if in_ver:
        m = re.match(r'^    strategy:\s*(\S+)', ln)
        if m:
            print("STRATEGY:" + unquote(m.group(1)))
    if in_con:
        m = re.match(r'^    - (.*)$', ln)
        if m:
            print("CONSTRAINT:" + unquote(m.group(1)))
PY
}

# V7 — static revision check. Never executes any part of a verify block.
V7_SHA_RE='^\^?[0-9a-fA-F]{7,40}([~^][0-9]*|\^\{(commit|)\})*$'
V7_HEAD_RE='^\^?(HEAD|FETCH_HEAD|ORIG_HEAD|MERGE_HEAD)([~^][0-9]*)*$'
V7_UNSAFE='[][$`()*?<>:\\]'

# The only git invocation V7 makes: fixed argv, read-only, ambient GIT_* redirection cleared.
v7_git() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
        -u GIT_ALTERNATE_OBJECT_DIRECTORIES git "$@"
}

# stdin: verify-block command lines. Prints `REV:<tok>` for each revision token
# and `SKIP:<tok>` for a candidate it cannot check statically. Only whitespace
# splitting: nothing is expanded or evaluated.
v7_tokens() {
    local seg i sub w a b
    local -a words
    while IFS= read -r seg; do
        read -ra words <<<"$seg"
        [ "${#words[@]}" -gt 0 ] && [ "${words[0]}" = git ] || continue
        i=1
        while [ "$i" -lt "${#words[@]}" ]; do
            case "${words[$i]}" in
                -C|-c) i=$((i+2)) ;;
                -*) i=$((i+1)) ;;
                *) break ;;
            esac
        done
        sub="${words[$i]:-}"
        [ -n "$sub" ] || continue
        for w in "${words[@]:$((i+1))}"; do
            [ "$w" = -- ] && break
            case "$w" in -*) continue ;; esac
            w="${w#[\"\']}"; w="${w%[\"\']}"
            if [ "$sub" = rev-parse ]; then
                if [[ "$w" =~ $V7_UNSAFE ]]; then echo "SKIP:$w"; else echo "REV:$w"; fi
            elif [[ "$w" =~ $V7_SHA_RE || "$w" =~ $V7_HEAD_RE ]]; then
                echo "REV:$w"
            elif [[ "$w" == *..* && "$w" != */* && "$w" != .* ]]; then
                if [[ "$w" =~ $V7_UNSAFE ]]; then echo "SKIP:$w"; continue; fi
                a="${w%%..*}"; b="${w#*..}"; b="${b#.}"
                [ -z "$a" ] || echo "REV:$a"
                [ -z "$b" ] || echo "REV:$b"
            fi
        done
    done < <(tr ';&|' '\n\n\n')
}

lint_wp_gates() {
    local wp="$1" wpn f base cmds toks t tok n blocks=0 in_repo=1
    wpn="$(basename -- "$wp")"
    v7_git -C "$wp" rev-parse --git-dir >/dev/null 2>&1 || in_repo=0
    for f in "$wp"/task-*.md; do
        [ -f "$f" ] || continue
        base="$(basename -- "$f")"
        cmds="$(verify_block "$f" | grep -vE '^\s*(#|$)')"
        [ -n "$cmds" ] || continue
        blocks=$((blocks+1))
        toks="$(printf '%s\n' "$cmds" | v7_tokens)"
        n=0
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            tok="${t#*:}"
            if [ "${t%%:*}" = SKIP ]; then
                echo "INFO [V7] $wpn: $base: token \`$tok\` not statically checkable"
                continue
            fi
            t="${tok#^}"; t="${t%^\{commit\}}"; t="${t%^\{\}}"
            case "$t" in ""|-*) continue ;; esac
            n=$((n+1))
            if [ "$in_repo" -eq 0 ]; then
                err V7 "$wpn: $base: names revision \`$tok\` but $wpn is not inside a git repository"
            elif ! v7_git -C "$wp" rev-parse --verify --quiet "$t^{commit}" >/dev/null 2>&1; then
                err V7 "$wpn: $base: gate names an unresolvable revision \`$tok\`"
            fi
        done <<EOF
$toks
EOF
        echo "INFO [V7] $wpn: $base: $n revision token(s) statically checked; gate not run"
    done
    [ "$blocks" -gt 0 ] || echo "INFO [V7] $wpn: no task verify: blocks to check; V7 ran no gate (schema-6 WPs carry none)"
}

# PI — path-idiom lint over the WP dir (OQ5). Findings ride the WARN channel;
# an unreadable input (its exit 2) is an ERROR.
lint_wp_path_idiom() {
    local wp="$1" out rc line
    out="$(bash "$SCRIPT_DIR/goalforge-path-idiom-lint.sh" "$wp" 2>&1)"; rc=$?
    case "$rc" in
        0) return 0 ;;
        1)
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                if [[ "$line" =~ ^(.*:[0-9]+):\ \[(PI[0-9]+)\]\ (.*)$ ]]; then
                    warn "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}: ${BASH_REMATCH[3]}"
                else
                    warn PI "$line"
                fi
            done <<EOF
$out
EOF
            ;;
        *) err PI "$(basename -- "$wp"): path-idiom lint could not scan (exit $rc): $(printf "%s" "${out##*$'\n'}" | sed "s/^goalforge-path-idiom-lint: //")" ;;
    esac
}

# V8 — every placeholder and file-shaped named artifact in goal.constraints resolves.
lint_wp_referents() {
    local wp="$1" refs con tok key val dir found
    refs="$(extract_goal_refs "$wp/overview.md" 2>/dev/null)"
    while IFS= read -r con; do
        [ -n "$con" ] || continue
        while IFS= read -r tok; do
            [ -n "$tok" ] || continue
            key="${tok#<}"; key="${key%>}"
            val="$(printf '%s\n' "$refs" | sed -n "s/^FIELD:$key=//p" | head -1)"
            case "$val" in ""|null|"<"*) err V8 "$(basename -- "$wp"): constraint placeholder $tok resolves to no populated frontmatter field" ;; esac
        done <<EOF
$(printf '%s' "$con" | grep -oE '<[A-Za-z_][A-Za-z0-9_-]*>')
EOF
        while IFS= read -r tok; do
            [ -n "$tok" ] || continue
            found=0; dir="$(cd "$wp" && pwd)"
            while :; do
                [ -e "$dir/$tok" ] && { found=1; break; }
                [ "$dir" = / ] && break
                dir="$(dirname "$dir")"
            done
            [ "$found" -eq 1 ] || err V8 "$(basename -- "$wp"): constraint names artifact \`$tok\`, which does not exist"
        done <<EOF
$(printf '%s' "$con" | grep -oE '`[^`[:space:]<>$*{}]+`' | tr -d '`' | grep -E '/|\.(md|sh|py|json|yaml|yml|txt|toml)$')
EOF
    done <<EOF
$(printf '%s\n' "$refs" | sed -n 's/^CONSTRAINT://p')
EOF
}

lint_wp() {
    local wp="$1" f base vb
    [ -d "$wp" ] || { echo "sdd-preharden-lint: not a directory: $wp" >&2; return 2; }

    # P1 — plugin-anchored paths anywhere in the WP's planning docs
    local m
    for f in "$wp"/overview.md "$wp"/task-*.md; do
        [ -f "$f" ] || continue
        base="$(basename -- "$f")"
        m="$(grep -oE '\$COGWRIGHT_ROOT|\$CLAUDE_PLUGIN_ROOT|plugins/cogwright' "$f" 2>/dev/null | head -1)"
        if [ -n "$m" ]; then
            warn P1 "$base: plugin-anchored path ($m) — local tree is authoritative"
        fi
    done

    # V1–V4 — per task verify: block
    for f in "$wp"/task-*.md; do
        [ -f "$f" ] || continue
        base="$(basename -- "$f")"
        vb="$(verify_block "$f")"
        [ -n "$vb" ] || continue

        if printf '%s' "$vb" | grep -q '|| true'; then
            warn V1 "$base: verify contains '|| true' — check can never fail"
        fi

        # commands = non-empty, non-comment lines
        local cmds echo_only
        cmds="$(printf '%s\n' "$vb" | grep -vE '^\s*(#|$)')"
        if [ -n "$cmds" ]; then
            # V2: every referenced path token that exists points inside the WP's own docs
            if printf '%s\n' "$cmds" | grep -qE '(grep|cat|test -f|\[ -f)' \
               && ! printf '%s\n' "$cmds" | grep -vE '(overview\.md|task-[a-z0-9-]*\.md|findings\.md|todo\.md)' | grep -qE '(grep|cat|test -f|\[ -f|bash|python3|pytest|sh |git )'; then
                warn V2 "$base: verify only inspects the WP's own planning docs (self-referential)"
            fi
            # V3: only echo/printf lines
            echo_only=1
            while IFS= read -r line; do
                printf '%s' "$line" | grep -qE '^\s*(echo|printf)\b' || { echo_only=0; break; }
            done <<EOF
$cmds
EOF
            [ "$echo_only" -eq 1 ] && warn V3 "$base: verify has no executable check (echo/printf only)"
            # V4: sole command is a --help probe
            if [ "$(printf '%s\n' "$cmds" | grep -c .)" -eq 1 ] && printf '%s' "$cmds" | grep -q -- '--help'; then
                warn V4 "$base: verify is a bare --help probe"
            fi
        fi
    done

    # V5 — WP-altitude command-shape + section-lint (ERROR channel, distinct
    # from the WARN channel above).
    lint_wp_verification "$wp"

    # V6 — heuristic live-corpus-root lint (WARN channel).
    lint_wp_behaviors "$wp"

    # V7 — static revision check (never runs a gate); V8 — resolve constraint
    # referents (ERROR channel); PI — path-idiom lint over the WP dir.
    lint_wp_gates "$wp"
    lint_wp_referents "$wp"
    lint_wp_path_idiom "$wp"

    if [ "$err_count" -gt 0 ]; then
        return 2
    fi
    [ "$warn_count" -eq 0 ]
}

self_test() {
    local d p=0 f=0
    d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
    ok(){ echo "  PASS: $1"; p=$((p+1)); }
    no(){ echo "  FAIL: $1"; f=$((f+1)); }
    echo "=== sdd-preharden-lint: --self-test ==="

    # dirty fixture: trips P1, V1, V2, V3, V4
    mkdir -p "$d/dirty"
    printf -- '---\nname: wp-x\n---\n## Goal\npath $COGWRIGHT_ROOT/scripts\n' > "$d/dirty/overview.md"
    printf -- '---\nname: task-01-a\nverify: |\n  bash run.sh || true\n---\nbody\n' > "$d/dirty/task-01-a.md"
    printf -- '---\nname: task-02-b\nverify: |\n  grep -q Goal overview.md\n---\nbody\n' > "$d/dirty/task-02-b.md"
    printf -- '---\nname: task-03-c\nverify: |\n  echo done\n---\nbody\n' > "$d/dirty/task-03-c.md"
    printf -- '---\nname: task-04-d\nverify: |\n  mytool --help\n---\nbody\n' > "$d/dirty/task-04-d.md"
    local out rc
    out="$(warn_count=0; lint_wp "$d/dirty")"; rc=$?
    [ "$rc" -eq 1 ] && ok "dirty WP -> exit 1" || no "dirty WP -> exit $rc (want 1)"
    for tag in P1 V1 V2 V3 V4; do
        printf '%s' "$out" | grep -q "\[$tag\]" && ok "dirty WP trips $tag" || no "dirty WP misses $tag ($out)"
    done

    # clean fixture: real check, repo file, no anchors
    mkdir -p "$d/clean"
    printf -- '---\nname: wp-y\n---\nlocal paths only\n' > "$d/clean/overview.md"
    printf -- '---\nname: task-01-real\nverify: |\n  bash scripts/run-tests.sh\n  grep -q slug src/slugger.py\n---\nbody\n' > "$d/clean/task-01-real.md"
    out="$(warn_count=0; lint_wp "$d/clean")"; rc=$?
    [ "$rc" -eq 0 ] && ok "clean WP -> exit 0" || no "clean WP -> exit $rc (want 0): $out"

    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

case "${1:-}" in
    --self-test) self_test; exit $? ;;
    "") echo "usage: goalforge-preharden-lint.sh <wp-dir> | --self-test" >&2; exit 2 ;;
    *) lint_wp "$1"; exit $? ;;
esac
