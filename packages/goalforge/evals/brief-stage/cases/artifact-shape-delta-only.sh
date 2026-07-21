#!/usr/bin/env bash
# brief-stage eval case (wp-06 task-05): the DELTA-ONLY artifact shape (A-FOLD).
# The emitted <wp>/brief-task-NN.md conforms exactly to the canonical schema:
#   - frontmatter keys are EXACTLY {task, created, brief_tier} — no more, no less,
#     and specifically NO `staleness_checked` (dropped per A-FOLD);
#   - body sections are References / Context / Skeleton plus a pointer to
#     task-NN.md for Steps and Acceptance;
#   - Steps and Acceptance are NOT duplicated into the brief (delta-only).
# Static shape assertion over a canonical fixture brief. Offline, deterministic.
set -uo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BRIEF="$TMP/brief-task-07-example.md"
cat > "$BRIEF" <<'EOF'
---
task: task-07-example
created: 2026-07-19
brief_tier: opus@high
---
## References
| file:line | git blob SHA |
| --- | --- |
| src/foo.py:12 | 1111111111111111111111111111111111111111 |
| goal:wp-06-brief-stage | abc123def456 |

## Context
Delta-only context: the constraints and surrounding-code facts the executor
needs, distilled — never the frozen implementation.

## Skeleton
```python
def foo(x: int) -> str: ...
```

See task-07-example.md for Steps and Acceptance (not duplicated here).
EOF

fail() { echo "FAIL: $1"; echo "--- brief ---"; cat "$BRIEF"; exit 1; }

# ── Frontmatter region (between the first two `---` fences) ──────────────────
fm="$(awk 'NR==1&&$0=="---"{inb=1;next} inb&&$0=="---"{exit} inb{print}' "$BRIEF")"

# Exactly the three permitted keys, nothing else.
keys="$(printf '%s\n' "$fm" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\):.*/\1/p' | sort)"
expected="$(printf 'brief_tier\ncreated\ntask\n')"
[ "$keys" = "$expected" ] || fail "frontmatter keys are not exactly {task, created, brief_tier}; got: $(echo "$keys" | tr '\n' ' ')"

printf '%s\n' "$fm" | grep -q '^staleness_checked:' && fail "frontmatter must NOT carry staleness_checked (dropped per A-FOLD)"

# ── Required delta-only sections ─────────────────────────────────────────────
grep -q '^## References$' "$BRIEF" || fail "missing ## References section"
grep -q '^## Context$'    "$BRIEF" || fail "missing ## Context section"
grep -q '^## Skeleton$'   "$BRIEF" || fail "missing ## Skeleton section"

# Pointer to task-NN.md for Steps/Acceptance.
grep -Eq 'task-[0-9]+[A-Za-z0-9-]*\.md' "$BRIEF" || fail "missing pointer to task-NN.md"

# Steps/Acceptance must NOT be duplicated as their own sections.
grep -q '^## Steps'      "$BRIEF" && fail "Steps must not be duplicated into the brief (delta-only)"
grep -q '^## Acceptance' "$BRIEF" && fail "Acceptance must not be duplicated into the brief (delta-only)"

echo "PASS: delta-only artifact shape — frontmatter exactly {task, created, brief_tier} (no staleness_checked); References/Context/Skeleton + task-NN.md pointer; no Steps/Acceptance duplication"
exit 0
