#!/usr/bin/env bash
# Deterministic structure harness for the prototype skill.
# Verifies the SKILL.md carries every load-bearing contract element.
set -u
SKILL="$(dirname "$0")/../SKILL.md"
fail=0

check() { # check <label> <grep-pattern>
  if grep -qiE "$2" "$SKILL"; then
    echo "PASS  $1"
  else
    echo "FAIL  $1  (pattern: $2)"
    fail=1
  fi
}

check "frontmatter name"            "^name: prototype$"
check "one-question gate"           "One question"
check "success-criteria gate"       "Success criteria required"
check "never-commits rule"          "prototype-never-commit"
check "keep-answer-delete-code"     "delete the code"
check "logic branch + LOGIC.md"     "LOGIC\.md"
check "ui branch + UI.md"           "UI\.md"
check "ui divergence (variations)"  "radically different"
check "worktree isolation"          "git worktree"
check "findings-as-data boundary"   "typed data"
check "declared spike register"     "Principle 2"
check "gotchas section"             "^## Gotchas"
check "pure logic module split"     "pure module|pure logic module"
check "interactive terminal harness" "terminal harness"
check "one command to run"          "One command to run"
check "ui variant switcher"         "variant="
check "structural difference rule"  "structurally different"
check "execution modes section"     "^## Execution modes"
check "explicit model+effort"       "Dispatch Routing Matrix"
check "independent verification"    "did not build"
check "absorb-through-review path"  "production register"
check "perf branch + PERF.md"       "PERF\.md"
check "perf baseline required"      "baseline"
check "perf correctness gate"       "Correctness gate"
check "perf scaling curve"          "scaling curve"
check "perf median + repetitions"   "median"
check "perf worth-it verdict"       "worth-it verdict"

exit $fail
