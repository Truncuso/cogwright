#!/usr/bin/env bash
# sdd-assumption-recheck.sh — re-run a WP's recorded `## Assumptions` checks and
# log any mismatch as a keyed, idempotent row in the WP's findings.md.
#
# Usage:
#   sdd-assumption-recheck.sh <wp-file>
#   sdd-assumption-recheck.sh --self-test
#
# Args:
#   <wp-file>  A WP markdown file (e.g. overview.md) carrying a `## Assumptions`
#              block. Mismatch rows are written to the SIBLING findings.md
#              (<dir-of-wp-file>/findings.md), created from the findings template
#              if absent.
#
# `## Assumptions` block format (author-written at harden):
#   ## Assumptions
#
#   - key: <stable-slug>               # the findings row is keyed on this
#     assumption: <one-line statement>
#     check: <shell command>           # OPTIONAL; author-trusted, RUN at recheck
#     expect: <substring of stdout>    # OPTIONAL
#
#   An entry with no `check:` is documentation-only (recorded, never re-run).
#   With `check:` + non-empty `expect:`, mismatch = `expect` is NOT a substring of
#   the command's stdout. With `check:` + empty `expect:`, mismatch = the command
#   exits non-zero.
#
# Trust boundary: the `check:` commands ARE author-written to be EXECUTED here
#   (the harden author wrote them and vouches for them). This is NOT the untrusted
#   task `verify:` string — that is verb-linted (command -v on the first token) and
#   NEVER executed. Keep the two separate.
#
# Output (idempotent by <key> — a re-run updates the row in place, never appends a
# duplicate):
#   ## [YYYY-MM-DD] Assumption mismatch: <key>
#   assumption: <text>
#   expected: <text>
#   actual: <text>
#   check-cmd: <text>
#
#   Plus a one-line summary on stdout. Exit 0 on a successful recheck — a mismatch
#   is LOGGED, never a hard-fail (execute Step 0b leaves the proceed/abort call to
#   operator judgment; the recheck is judgment, not a deterministic gate). Exit 1
#   on an operational error (missing <wp-file>, PyYAML-independent — pure stdlib).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,44p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Parse `## Assumptions`, run trusted check cmds, keyed-idempotent write ──────
recheck() {
    python3 - "$1" "$(date +%F)" <<'PY'
import sys, re, os, subprocess
from pathlib import Path

wp_file = Path(sys.argv[1])
today = sys.argv[2]

if not wp_file.is_file():
    sys.stderr.write("ERROR: wp-file not found: %s\n" % wp_file); sys.exit(1)

text = wp_file.read_text(encoding="utf-8")
lines = text.split("\n")

# ── Extract the `## Assumptions` section (stop at the next `## ` header) ──
sec = []
in_sec = False
for ln in lines:
    if re.match(r"^##\s+Assumptions\s*$", ln):
        in_sec = True
        continue
    if in_sec:
        if re.match(r"^##\s+", ln):
            break
        sec.append(ln)

# ── Parse entries: `- key:` opens an entry; indented field lines fill it ──
entries = []
cur = None
def flush():
    global cur
    if cur is not None and cur.get("key"):
        entries.append(cur)
    cur = None

for ln in sec:
    m = re.match(r"^\s*-\s+key:\s*(.+?)\s*$", ln)
    if m:
        flush()
        cur = {"key": m.group(1).strip(), "assumption": "", "check": None, "expect": ""}
        continue
    if cur is not None:
        fm = re.match(r"^\s+(assumption|check|expect):\s*(.*)$", ln)
        if fm:
            field, val = fm.group(1), fm.group(2).strip()
            cur[field] = val
flush()

# ── Run each trusted check cmd; collect mismatches ──
# `actual` is FLATTENED to one line before it is embedded in findings.md. Raw
# stdout may contain a line beginning with "## ", which would otherwise be read as
# a section header by the keyed-upsert end-scan and corrupt findings.md on the next
# re-run (a short end → orphaned block tail). Substring matching uses the RAW
# stdout; only the stored representation is flattened.
timeout_s = int(os.environ.get("SDD_ASSUMPTION_CHECK_TIMEOUT", "30"))

def flat(s):
    return s.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n")

mismatches = []
checked = 0
for e in entries:
    if not e["check"]:
        continue   # documentation-only assumption — never re-run
    checked += 1
    expect = e["expect"].strip()
    try:
        proc = subprocess.run(e["check"], shell=True, capture_output=True,
                              text=True, timeout=timeout_s)
        out, rc, timed_out = (proc.stdout or "").strip(), proc.returncode, False
    except subprocess.TimeoutExpired:
        out, rc, timed_out = "", None, True
    if timed_out:
        # a hung check must not block the execute preflight — log as a mismatch
        mismatch = True
        actual_repr = "(check timed out after %ds)" % timeout_s
        expected_repr = expect if expect else "(command exits 0)"
    elif expect:
        mismatch = expect not in out
        actual_repr = flat(out) if out else "(no stdout; exit %d)" % rc
        expected_repr = expect
    else:
        mismatch = rc != 0
        prefix = flat(out) + " " if out else ""
        actual_repr = prefix + "(exit %d)" % rc
        expected_repr = "(command exits 0)"
    if mismatch:
        mismatches.append({
            "key": e["key"], "assumption": e["assumption"],
            "expected": expected_repr, "actual": actual_repr, "check": e["check"],
        })

# ── Keyed, idempotent write to the sibling findings.md ──
findings = wp_file.parent / "findings.md"

def render(m):
    return "\n".join([
        "## [%s] Assumption mismatch: %s" % (today, m["key"]),
        "assumption: %s" % m["assumption"],
        "expected: %s" % m["expected"],
        "actual: %s" % m["actual"],
        "check-cmd: %s" % m["check"],
    ])

def minimal_findings():
    slug = wp_file.parent.name
    return "\n".join([
        "<!-- Template: findings v4 (frontmatter-first, flat layout) -->",
        "---",
        "name: %s-findings" % slug,
        "title: %s findings" % slug,
        "updated: %s" % today,
        "---",
        "",
    ]) + "\n"

def upsert(ftext, m):
    block = render(m)
    flines = ftext.split("\n")
    # match the keyed header regardless of date → re-run updates in place
    hdr = re.compile(r"^##\s+\[[^\]]*\]\s+Assumption mismatch:\s+" + re.escape(m["key"]) + r"\s*$")
    start = None
    for i, l in enumerate(flines):
        if hdr.match(l):
            start = i; break
    if start is None:
        body = ftext.rstrip("\n")
        return (body + "\n\n" + block + "\n") if body else (block + "\n")
    end = len(flines)
    for j in range(start + 1, len(flines)):
        if flines[j].startswith("## "):
            end = j; break
    before = flines[:start]
    after = flines[end:]
    while before and before[-1].strip() == "":
        before.pop()
    while after and after[0].strip() == "":
        after.pop(0)
    chunks = []
    if before:
        chunks.append("\n".join(before))
    chunks.append(block)
    if after:
        chunks.append("\n".join(after))
    return "\n\n".join(chunks) + "\n"

if mismatches:
    ftext = findings.read_text(encoding="utf-8") if findings.exists() else minimal_findings()
    for m in mismatches:
        ftext = upsert(ftext, m)
    findings.write_text(ftext, encoding="utf-8")

if mismatches:
    keys = ", ".join(m["key"] for m in mismatches)
    print("assumption-recheck: %d checked, %d mismatch (%s). Logged to %s — operator decides whether to proceed."
          % (checked, len(mismatches), keys, findings))
else:
    print("assumption-recheck: %d checked, 0 mismatch." % checked)
PY
}

# ── Self-test ───────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local t_pass=0 t_fail=0 d
    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    d="$_ST_TMP"

    # specific names so the defs (always global in bash) don't shadow anything;
    # unset at the end of self_test for cleanliness.
    _st_ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    _st_no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }

    # count_re <ERE> <file> — integer on stdout, always exit 0 (no grep-exit / pipefail trap)
    count_re() { awk -v re="$1" '$0 ~ re { n++ } END { print n+0 }' "$2"; }

    echo "=== sdd-assumption-recheck.sh --self-test ==="

    # ── Fixture: a WP dir mirroring the real layout — overview.md with a
    # `## Assumptions` block (one TRUE, one seeded-FALSE, one documentation-only)
    # and a findings.md mirroring the real findings v4 row shape. ──
    local wp="$d/wp-01-fixture"
    mkdir -p "$wp"
    cat > "$wp/overview.md" << 'EOF'
---
name: wp-01-fixture
status: ready
---

## Goal

Fixture WP for the assumption-recheck self-test.

## Assumptions

- key: true-assumption
  assumption: echo emits the literal token ok-here
  check: echo ok-here
  expect: ok-here
- key: false-assumption
  assumption: a seeded false assumption — actual will not contain expected
  check: echo actual-value
  expect: expected-value
- key: doc-only
  assumption: a documentation-only assumption with no check command
EOF

    cat > "$wp/findings.md" << 'EOF'
<!-- Template: findings v4 (frontmatter-first, flat layout) -->
---
name: wp-01-fixture-findings
title: wp-01-fixture findings
updated: 2026-06-24
---

## [2026-06-24] Resolution: seeded prior entry
Decision: keep this entry intact across rechecks.
EOF

    # ── Run 1: seeded false assumption → exactly one keyed mismatch row ──
    local out1
    out1="$(bash "$SELF" "$wp/overview.md")"

    if [[ "$(count_re 'Assumption mismatch: false-assumption$' "$wp/findings.md")" == "1" ]]; then
        _st_ok "false-assumption-emits-one-row"
    else
        _st_no "false-assumption-emits-one-row" "got $(count_re 'Assumption mismatch: false-assumption$' "$wp/findings.md")"
    fi

    if grep -q 'Assumption mismatch: true-assumption' "$wp/findings.md"; then
        _st_no "true-assumption-emits-no-row" "a holding assumption must not log a row"
    else
        _st_ok "true-assumption-emits-no-row"
    fi

    if grep -q 'Assumption mismatch: doc-only' "$wp/findings.md"; then
        _st_no "doc-only-skipped" "a check-less assumption must not be re-run"
    else
        _st_ok "doc-only-skipped"
    fi

    # row schema mirrors the real findings.md row shape
    if grep -q '^assumption: a seeded false assumption' "$wp/findings.md" \
       && grep -q '^expected: expected-value$' "$wp/findings.md" \
       && grep -q '^actual: actual-value$' "$wp/findings.md" \
       && grep -q '^check-cmd: echo actual-value$' "$wp/findings.md"; then
        _st_ok "row-schema-fields"
    else
        _st_no "row-schema-fields" "missing one of assumption/expected/actual/check-cmd"
    fi

    # pre-existing finding preserved (not clobbered)
    if [[ "$(count_re 'Resolution: seeded prior entry$' "$wp/findings.md")" == "1" ]]; then
        _st_ok "prior-finding-preserved"
    else
        _st_no "prior-finding-preserved" "got $(count_re 'Resolution: seeded prior entry$' "$wp/findings.md")"
    fi

    if echo "$out1" | grep -q '1 mismatch'; then
        _st_ok "summary-reports-mismatch"
    else
        _st_no "summary-reports-mismatch" "out=$out1"
    fi

    # ── Run 2: idempotency — re-run must NOT duplicate the keyed row ──
    bash "$SELF" "$wp/overview.md" >/dev/null
    if [[ "$(count_re 'Assumption mismatch: false-assumption$' "$wp/findings.md")" == "1" ]]; then
        _st_ok "idempotent-no-duplicate"
    else
        _st_no "idempotent-no-duplicate" "got $(count_re 'Assumption mismatch: false-assumption$' "$wp/findings.md")"
    fi

    if grep -qF '<!-- Template: findings v4' "$wp/findings.md"; then
        _st_ok "findings-template-marker-intact"
    else
        _st_no "findings-template-marker-intact" "marker lost"
    fi

    # ── Create-if-absent: a false assumption with no pre-existing findings.md ──
    local wp2="$d/wp-02-nofindings"
    mkdir -p "$wp2"
    cat > "$wp2/overview.md" << 'EOF'
## Assumptions

- key: missing-tool
  assumption: a tool that is not on PATH is available
  check: command -v definitely-not-a-real-binary-xyz
EOF
    bash "$SELF" "$wp2/overview.md" >/dev/null
    if [[ -f "$wp2/findings.md" ]] \
       && grep -qF '<!-- Template: findings v4' "$wp2/findings.md" \
       && [[ "$(count_re 'Assumption mismatch: missing-tool$' "$wp2/findings.md")" == "1" ]]; then
        _st_ok "create-findings-if-absent"
    else
        _st_no "create-findings-if-absent" "findings.md not created with keyed row"
    fi

    # ── Multi-line stdout containing a "## " line → must be flattened, not corrupt ──
    # Regression guard: an un-flattened `## ...` line in `actual` would be read as a
    # section header by upsert()'s end-scan and orphan the block tail on re-run.
    local wp3="$d/wp-03-multiline"
    mkdir -p "$wp3"
    cat > "$wp3/overview.md" << 'EOF'
## Assumptions

- key: multiline-probe
  assumption: stdout spans multiple lines including a header-like line
  check: printf 'line one\n## injected header line\nline three\n'
  expect: not-in-the-output
EOF
    cat > "$wp3/findings.md" << 'EOF'
<!-- Template: findings v4 (frontmatter-first, flat layout) -->
---
name: wp-03-multiline-findings
title: wp-03 findings
updated: 2026-06-24
---

## [2026-06-24] Resolution: prior entry that must survive
Decision: keep intact.
EOF
    bash "$SELF" "$wp3/overview.md" >/dev/null
    bash "$SELF" "$wp3/overview.md" >/dev/null   # re-run: would corrupt if not flattened
    if [[ "$(count_re 'Assumption mismatch: multiline-probe$' "$wp3/findings.md")" == "1" ]] \
       && [[ "$(count_re '^## injected header line$' "$wp3/findings.md")" == "0" ]] \
       && [[ "$(count_re '^check-cmd: ' "$wp3/findings.md")" == "1" ]] \
       && grep -qF 'actual: line one\n## injected header line\nline three' "$wp3/findings.md" \
       && [[ "$(count_re 'Resolution: prior entry that must survive$' "$wp3/findings.md")" == "1" ]]; then
        _st_ok "multiline-stdout-flattened-no-corruption"
    else
        _st_no "multiline-stdout-flattened-no-corruption" "injected ## line or orphaned tail in findings.md"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    unset -f _st_ok _st_no count_re
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ──────────────────────────────────────────────────────────
SELFTEST=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELFTEST=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        --*)         echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)           POS+=("$1"); shift ;;
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

if [[ "${#POS[@]}" -lt 1 ]]; then
    echo "ERROR: usage: sdd-assumption-recheck.sh <wp-file>" >&2
    exit 1
fi

WP_FILE="${POS[0]}"
[[ -f "$WP_FILE" ]] || { echo "ERROR: wp-file not found: $WP_FILE" >&2; exit 1; }

recheck "$WP_FILE"
