#!/usr/bin/env bash
# Mutation harness for the interview specialization eval block in run.sh.
# Proves the block fails for the right reasons: each mutation below removes
# exactly one piece of the interview wiring in a fresh scratch copy of the
# package, and run.sh must go red for it. Offline, no network.
#
# Exit 0 only if: baseline is green AND all 6 mutations turn run.sh red.
#
# Not covered here: a paraphrase-fork mutation (rewording interview/SKILL.md's
# delegation language so it drifts from interview-loop's actual contract while
# keeping every grepped token intact) — that is a semantic check no grep guard
# can catch; left as a human/reviewer concern, not a mutation case.

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$EVALS_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAIL=0

# fresh_copy <label> — makes an isolated scratch copy of the package and
# echoes its path. run.sh computes SKILL_DIR relative to itself, so the
# scratch copy is fully self-contained; the engine-drift guard reads
# $HOME/.claude/skills/interview-loop/SKILL.md, which lives outside the
# package and is unaffected by any of these mutations.
fresh_copy() {
  local label="$1"
  local dst="$TMP_ROOT/$label"
  cp -r "$PKG_DIR" "$dst"
  echo "$dst"
}

# ── Baseline: unmutated scratch copy must be green ──────────────────────────
BASELINE_DIR="$(fresh_copy baseline)"
if bash "$BASELINE_DIR/evals/run.sh" >/dev/null 2>&1; then
  echo "PASS: baseline (unmutated scratch copy) is green"
else
  echo "FAIL: baseline (unmutated scratch copy) is green"
  FAIL=1
fi

# ── Mutation (a): delete interview/SKILL.md ─────────────────────────────────
DIR_A="$(fresh_copy mutation-a)"
rm -f "$DIR_A/interview/SKILL.md"
if bash "$DIR_A/evals/run.sh" >/dev/null 2>&1; then
  echo "FAIL: mutation (a) delete interview/SKILL.md turns run.sh red"
  FAIL=1
else
  echo "PASS: mutation (a) delete interview/SKILL.md turns run.sh red"
fi

# ── Mutation (b): strip the escape-hatch phrase from interview/SKILL.md ────
DIR_B="$(fresh_copy mutation-b)"
python3 - "$DIR_B/interview/SKILL.md" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("above discussion fidelity", "REDACTED")
open(path, "w", encoding="utf-8").write(text)
PYEOF
if bash "$DIR_B/evals/run.sh" >/dev/null 2>&1; then
  echo "FAIL: mutation (b) strip escape-hatch phrase turns run.sh red"
  FAIL=1
else
  echo "PASS: mutation (b) strip escape-hatch phrase turns run.sh red"
fi

# ── Mutation (c): remove goalforge-interview references from harden/SKILL.md
DIR_C="$(fresh_copy mutation-c)"
python3 - "$DIR_C/harden/SKILL.md" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("goalforge-interview", "REDACTED")
open(path, "w", encoding="utf-8").write(text)
PYEOF
if bash "$DIR_C/evals/run.sh" >/dev/null 2>&1; then
  echo "FAIL: mutation (c) remove goalforge-interview refs from harden/SKILL.md turns run.sh red"
  FAIL=1
else
  echo "PASS: mutation (c) remove goalforge-interview refs from harden/SKILL.md turns run.sh red"
fi

# ── Mutation (d): delete fidelity.md's escape-hatch row ─────────────────────
DIR_D="$(fresh_copy mutation-d)"
python3 - "$DIR_D/references/fidelity.md" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
lines = [l for l in lines if "goalforge-interview` escape hatch" not in l]
open(path, "w", encoding="utf-8").writelines(lines)
PYEOF
if bash "$DIR_D/evals/run.sh" >/dev/null 2>&1; then
  echo "FAIL: mutation (d) delete fidelity.md escape-hatch row turns run.sh red"
  FAIL=1
else
  echo "PASS: mutation (d) delete fidelity.md escape-hatch row turns run.sh red"
fi

# ── Mutation (e): reinsert the stale 'planned — wp-06' marker into fidelity.md's
# escape-hatch row ─────────────────────────────────────────────────────────
DIR_E="$(fresh_copy mutation-e)"
python3 - "$DIR_E/references/fidelity.md" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "`goalforge-interview` escape hatch",
    "`goalforge-interview` escape hatch (planned — wp-06)",
)
open(path, "w", encoding="utf-8").write(text)
PYEOF
if bash "$DIR_E/evals/run.sh" >/dev/null 2>&1; then
  echo "FAIL: mutation (e) reinsert planned-wp-06 marker turns run.sh red"
  FAIL=1
else
  echo "PASS: mutation (e) reinsert planned-wp-06 marker turns run.sh red"
fi

# ── Mutation (f): delete the goalforge-interview row from the parent SKILL.md's
# Children table ────────────────────────────────────────────────────────────
DIR_F="$(fresh_copy mutation-f)"
python3 - "$DIR_F/SKILL.md" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
lines = [l for l in lines if "`goalforge-interview`" not in l]
open(path, "w", encoding="utf-8").writelines(lines)
PYEOF
if bash "$DIR_F/evals/run.sh" >/dev/null 2>&1; then
  echo "FAIL: mutation (f) delete goalforge-interview row from parent SKILL.md turns run.sh red"
  FAIL=1
else
  echo "PASS: mutation (f) delete goalforge-interview row from parent SKILL.md turns run.sh red"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "=== interview-mutations: all checks passed ==="
  exit 0
else
  echo "=== interview-mutations: FAILURES DETECTED ==="
  exit 1
fi
