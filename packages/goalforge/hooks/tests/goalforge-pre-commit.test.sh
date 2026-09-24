#!/usr/bin/env bash
# Regression test for goalforge-pre-commit.sh — block + allow cases.
# Focus: the full-tree-feature-gated validation fix. A staged feature carrying a
# legitimate CROSS-FEATURE edge ([[sibling-feature]]) must ALLOW (the sibling
# resolves in a full-tree walk); a staged feature with its OWN schema error must
# BLOCK. Hermetic: builds a throwaway git repo, stages, runs the hook, asserts rc.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/goalforge-pre-commit.sh"
VALIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/goalforge-validate.sh"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
no() { echo "FAIL: $1 — $2"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
git -C "$TMP" config user.email t@t.t
git -C "$TMP" config user.name t

mk_feature() { # <slug> <status> [relationships-block]
    local slug="$1" status="$2" rel="${3:-}"
    local d="$TMP/plans/$slug"
    mkdir -p "$d"
    {
        echo "---"
        echo "name: $slug"
        echo "title: $slug"
        echo "status: $status"
        echo "created: 2026-06-29"
        echo "feature: $slug"
        echo "work_packages: []"
        printf '%s' "$rel"
        echo "---"
        echo ""
        echo "## Problem"
        echo "x"
    } > "$d/overview.md"
}

run_hook() { # runs the hook with the staged index of $TMP; echoes rc
    ( cd "$TMP" && GOALFORGE_VALIDATE_SCRIPT="$VALIDATE" bash "$HOOK" >/dev/null 2>&1 )
    echo $?
}

# A stable sibling target so the cross-feature wikilink resolves on a full walk.
mk_feature foundation ready
git -C "$TMP" add -A >/dev/null; git -C "$TMP" commit -qm seed

# ── ALLOW: a clean feature whose overview carries a cross-feature edge ─────────
REL=$'relationships:\n  - depends_on: [[foundation]]\n'
mk_feature consumer ready "$REL"
git -C "$TMP" add plans/consumer/overview.md >/dev/null
rc=$(run_hook)
if [[ "$rc" -eq 0 ]]; then ok "allow-cross-feature-edge"; else no "allow-cross-feature-edge" "rc=$rc (expected 0)"; fi
git -C "$TMP" add -A >/dev/null; git -C "$TMP" commit -qm consumer

# ── BLOCK: a feature with its OWN invalid status enum ─────────────────────────
mk_feature broken not-a-valid-status
git -C "$TMP" add plans/broken/overview.md >/dev/null
rc=$(run_hook)
if [[ "$rc" -eq 1 ]]; then ok "block-own-error"; else no "block-own-error" "rc=$rc (expected 1)"; fi

# ── BLOCK with a POISONED CLAUDE_PLUGIN_ROOT ──────────────────────────────────
# The hook runs in whatever environment the invoking git tool carries, so its
# default validator address must not be steerable by one: with the same broken
# feature staged, a bogus CLAUDE_PLUGIN_ROOT and NO GOALFORGE_VALIDATE_SCRIPT,
# the script-relative default must still resolve and still block. If the hook
# ever reads that variable again this case turns green-to-red (skip notice on
# stderr, rc 0).
rc=$( ( cd "$TMP" && CLAUDE_PLUGIN_ROOT=/nonexistent bash "$HOOK" >/dev/null 2>&1 ); echo $? )
if [[ "$rc" -eq 1 ]]; then ok "block-with-poisoned-CLAUDE_PLUGIN_ROOT"; else no "block-with-poisoned-CLAUDE_PLUGIN_ROOT" "rc=$rc (expected 1)"; fi

# ── PLANS-REPO-ROOTED layout (goalforge-plans-root.sh leg 2b) ──────────────────
# The plans tree kept as its OWN git repo — the git root is itself named
# `plans`, so staged paths are rooted directly at the feature (no `plans/`
# path segment at all). Without the fix, the plans/<feature>/ predicate
# extracts zero features from every such path and the hook never validates.
TMP2="$(mktemp -d)/plans"
mkdir -p "$TMP2"
trap 'rm -rf "$TMP"; rm -rf "$(dirname "$TMP2")"' EXIT
git -C "$TMP2" init -q
git -C "$TMP2" config user.email t@t.t
git -C "$TMP2" config user.name t

mk_feature_rooted() { # <slug> <status> [relationships-block]
    local slug="$1" status="$2" rel="${3:-}"
    local d="$TMP2/$slug"
    mkdir -p "$d"
    {
        echo "---"
        echo "name: $slug"
        echo "title: $slug"
        echo "status: $status"
        echo "created: 2026-06-29"
        echo "feature: $slug"
        echo "work_packages: []"
        printf '%s' "$rel"
        echo "---"
        echo ""
        echo "## Problem"
        echo "x"
    } > "$d/overview.md"
}

run_hook_rooted() { # runs the hook with the staged index of $TMP2; echoes rc
    ( cd "$TMP2" && GOALFORGE_VALIDATE_SCRIPT="$VALIDATE" bash "$HOOK" >/dev/null 2>&1 )
    echo $?
}

mk_feature_rooted foundation2 ready
git -C "$TMP2" add -A >/dev/null; git -C "$TMP2" commit -qm seed

# ── ALLOW (plans-repo-rooted): a clean feature ─────────────────────────────────
mk_feature_rooted consumer2 ready
git -C "$TMP2" add consumer2/overview.md >/dev/null
rc=$(run_hook_rooted)
if [[ "$rc" -eq 0 ]]; then ok "plans-repo-rooted: allow-clean-feature"; else no "plans-repo-rooted: allow-clean-feature" "rc=$rc (expected 0)"; fi
git -C "$TMP2" add -A >/dev/null; git -C "$TMP2" commit -qm consumer2

# ── BLOCK (plans-repo-rooted): a feature with its OWN invalid status enum ──────
mk_feature_rooted broken2 not-a-valid-status
git -C "$TMP2" add broken2/overview.md >/dev/null
rc=$(run_hook_rooted)
if [[ "$rc" -eq 1 ]]; then ok "plans-repo-rooted: block-own-error"; else no "plans-repo-rooted: block-own-error" "rc=$rc (expected 1)"; fi
git -C "$TMP2" reset >/dev/null

# ── human_required set-once invariant (ticket-72, commit-time backstop) ───────
# goalforge-single-writer.sh guards human_required on TOOL writes only; a
# `sed -i` through Bash bypasses its matcher entirely. These cases pin the
# commit-time gate. A PASSING STUB validator is used deliberately: the unit
# under test is the human_required comparison, not schema validation, so the
# stub keeps rc 2 attributable to this gate and rc 0 free of sibling-owned
# schema data that another task may rewrite.
git -C "$TMP" reset >/dev/null
STUB="$TMP/stub-validate.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB"
chmod +x "$STUB"

run_hook_stub() { # runs the hook against $TMP's index with validation stubbed out
    ( cd "$TMP" && GOALFORGE_VALIDATE_SCRIPT="$STUB" bash "$HOOK" >/dev/null 2>&1 )
    echo $?
}

mk_wp() { # <feature> <wp-slug> <human_required-value-literal>
    local d="$TMP/plans/$1/$2"
    mkdir -p "$d"
    {
        echo "---"
        echo "name: $2"
        echo "title: $2"
        echo "status: ready"
        echo "human_required: $3"
        echo "plan: $1"
        echo "---"
        echo ""
        echo "## Goal"
        echo "x"
    } > "$d/overview.md"
}

hr_feature=hrgate
mk_wp "$hr_feature" wp-set '"reason A"'
mk_wp "$hr_feature" wp-null 'null'
git -C "$TMP" add -A >/dev/null; git -C "$TMP" commit -qm hr-seed

# BLOCK: an already-set reason replaced by a DIFFERENT reason.
sed -i 's/reason A/reason B/' "$TMP/plans/$hr_feature/wp-set/overview.md"
git -C "$TMP" add "plans/$hr_feature/wp-set/overview.md" >/dev/null
rc=$(run_hook_stub)
if [[ "$rc" -eq 2 ]]; then ok "human_required: set -> different reason -> block"; else no "human_required: set -> different reason -> block" "rc=$rc (expected 2)"; fi
git -C "$TMP" reset >/dev/null; git -C "$TMP" checkout -- "plans/$hr_feature/wp-set/overview.md"

# BLOCK: an already-set reason cleared to null — the exact `sed -i` bypass.
sed -i 's/human_required: "reason A"/human_required: null/' "$TMP/plans/$hr_feature/wp-set/overview.md"
git -C "$TMP" add "plans/$hr_feature/wp-set/overview.md" >/dev/null
rc=$(run_hook_stub)
if [[ "$rc" -eq 2 ]]; then ok "human_required: set -> null (clear) -> block"; else no "human_required: set -> null (clear) -> block" "rc=$rc (expected 2)"; fi
git -C "$TMP" reset >/dev/null; git -C "$TMP" checkout -- "plans/$hr_feature/wp-set/overview.md"

# BLOCK: the field removed from the frontmatter entirely.
sed -i '/human_required:/d' "$TMP/plans/$hr_feature/wp-set/overview.md"
git -C "$TMP" add "plans/$hr_feature/wp-set/overview.md" >/dev/null
rc=$(run_hook_stub)
if [[ "$rc" -eq 2 ]]; then ok "human_required: field removed -> block"; else no "human_required: field removed -> block" "rc=$rc (expected 2)"; fi
git -C "$TMP" reset >/dev/null; git -C "$TMP" checkout -- "plans/$hr_feature/wp-set/overview.md"

# ALLOW: null -> "<reason>" is the one sanctioned transition.
sed -i 's/human_required: null/human_required: "newly required"/' "$TMP/plans/$hr_feature/wp-null/overview.md"
git -C "$TMP" add "plans/$hr_feature/wp-null/overview.md" >/dev/null
rc=$(run_hook_stub)
if [[ "$rc" -eq 0 ]]; then ok "human_required: null -> reason (set) -> allow"; else no "human_required: null -> reason (set) -> allow" "rc=$rc (expected 0)"; fi
git -C "$TMP" reset >/dev/null; git -C "$TMP" checkout -- "plans/$hr_feature/wp-null/overview.md"

# ALLOW: human_required untouched while another frontmatter field changes.
sed -i 's/^status: ready/status: implemented/' "$TMP/plans/$hr_feature/wp-set/overview.md"
git -C "$TMP" add "plans/$hr_feature/wp-set/overview.md" >/dev/null
rc=$(run_hook_stub)
if [[ "$rc" -eq 0 ]]; then ok "human_required: unchanged alongside another edit -> allow"; else no "human_required: unchanged alongside another edit -> allow" "rc=$rc (expected 0)"; fi
git -C "$TMP" reset >/dev/null; git -C "$TMP" checkout -- "plans/$hr_feature/wp-set/overview.md"

# ALLOW: a brand-new WP overview that already carries a reason (no HEAD blob).
mk_wp "$hr_feature" wp-new '"born gated"'
git -C "$TMP" add "plans/$hr_feature/wp-new/overview.md" >/dev/null
rc=$(run_hook_stub)
if [[ "$rc" -eq 0 ]]; then ok "human_required: new file with a reason -> allow"; else no "human_required: new file with a reason -> allow" "rc=$rc (expected 0)"; fi
git -C "$TMP" reset >/dev/null

# ── admitted-providers.yaml guard (wp-08 T7 / b9) ─────────────────────────────
# A staged change that ADDS or CHANGES an `admitted:` row blocks unless the user
# confirms on the controlling terminal. Each fixture runs in its own throwaway
# repo whose HEAD holds the base table; the index holds the change.
TMP9="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -rf "$(dirname "$TMP2")"; rm -rf "$TMP9"' EXIT
TBL="packages/goalforge/references/admitted-providers.yaml"
MIRROR="plugins/goalforge/references/admitted-providers.yaml"
ROW1=$'  - task_class: code/py\n    provider: ollama\n    model: glm-5.3:cloud\n    leaf: skills/x/headless_dispatch\n    leaf_sha256: 0000000000000000000000000000000000000000000000000000000000000000\n    evidence: {kind: user-experience, ref: fx#1}\n    permission_set: [read]\n    max_egress: overview\n'
ROW2="${ROW1//code\/py/code\/sh}"
ONE_ROW=$'schema_version: 1\nadmitted:\n'"$ROW1"
TWO_ROWS="$ONE_ROW$ROW2"
EMPTY_FLOW=$'schema_version: 1\nadmitted: []\n'
FLOW_ADD=$'schema_version: 1\nadmitted: [{task_class: code/py, provider: ollama, model: glm-5.3:cloud, leaf: skills/x/headless_dispatch, leaf_sha256: "0000", evidence: {kind: user-experience, ref: fx}, permission_set: [read], max_egress: overview}]\n'
GQ=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.email=t@t.t -c user.name=t -c commit.gpgsign=false)

# fixture_repo <name> <path> <HEAD content> <index content> -> prints repo dir
fixture_repo() {
    local d="$TMP9/$1"
    mkdir -p "$d/$(dirname "$2")"
    "${GQ[@]}" -C "$d" init -q
    printf '%s' "$3" > "$d/$2"
    "${GQ[@]}" -C "$d" add -A; "${GQ[@]}" -C "$d" commit -qm base
    if [[ "$4" == "<delete>" ]]; then
        "${GQ[@]}" -C "$d" rm -q "$2"
    else
        printf '%s' "$4" > "$d/$2"; "${GQ[@]}" -C "$d" add -A
    fi
    printf '%s' "$d"
}

# Conditions. (i) no controlling TTY, no seam override; (iv) the same with `y`
# on stdin; (v) an `export -f`'d seam answering yes, the hook a child process;
# (ii)/(iii) the hook SOURCED, the seam redefined after sourcing, and the
# exposed outer wrapper called — so the wrapper's exit-code mapping is in the loop.
cond_i()   { ( cd "$1" && setsid -w bash "$HOOK" </dev/null >/dev/null 2>"$TMP9/err" ); echo $?; }
cond_iv()  { ( cd "$1" && printf 'y\n' | setsid -w bash "$HOOK" >/dev/null 2>"$TMP9/err" ); echo $?; }
cond_v()   { ( cd "$1" && _gf_admitted_confirm() { return 0; } && export -f _gf_admitted_confirm \
               && setsid -w bash "$HOOK" </dev/null >/dev/null 2>"$TMP9/err" ); echo $?; }
cond_seam() { # <repo> <0=yes|1=no>
    ( cd "$1" && source "$HOOK" && eval "_gf_admitted_confirm() { return $2; }" \
        && goalforge_pre_commit </dev/null >/dev/null 2>"$TMP9/err" ); echo $?
}
blocked_msg() { grep -q 'admitted-providers.yaml' "$TMP9/err" && grep -q 'INTERACTIVE confirmation' "$TMP9/err"; }

check_block_fixture() { # <label> <repo>
    local label="$1" repo="$2" rc c
    for c in i ii iv v; do
        case "$c" in
            i)  rc=$(cond_i "$repo") ;;
            ii) rc=$(cond_seam "$repo" 1) ;;
            iv) rc=$(cond_iv "$repo") ;;
            v)  rc=$(cond_v "$repo") ;;
        esac
        if [[ "$rc" -eq 2 ]] && blocked_msg; then ok "b9 $label under ($c) -> block naming admitted-providers.yaml + INTERACTIVE confirmation"
        else no "b9 $label under ($c) -> block" "rc=$rc err=$(cat "$TMP9/err")"; fi
    done
    rc=$(cond_seam "$repo" 0)
    if [[ "$rc" -eq 0 ]]; then ok "b9 $label under (iii) seam answers yes -> allow"
    else no "b9 $label under (iii) -> allow" "rc=$rc err=$(cat "$TMP9/err")"; fi
}

check_block_fixture "A block-style add"          "$(fixture_repo A "$TBL" "$ONE_ROW" "$TWO_ROWS")"
check_block_fixture "B flow-style add"           "$(fixture_repo B "$TBL" "$EMPTY_FLOW" "$FLOW_ADD")"
check_block_fixture "C1 in-place provider edit"  "$(fixture_repo C1 "$TBL" "$ONE_ROW" "${ONE_ROW/provider: ollama/provider: zai}")"
check_block_fixture "C2 in-place model edit"     "$(fixture_repo C2 "$TBL" "$ONE_ROW" "${ONE_ROW/model: glm-5.3:cloud/model: glm-9:cloud}")"
check_block_fixture "C3 in-place leaf edit"      "$(fixture_repo C3 "$TBL" "$ONE_ROW" "${ONE_ROW/leaf: skills\/x/leaf: skills\/y}")"
check_block_fixture "H plugin-mirror add"        "$(fixture_repo H "$MIRROR" "$ONE_ROW" "$TWO_ROWS")"

for pair in "D comment-only edit|# a comment"$'\n'"$ONE_ROW" "E row removal|$EMPTY_FLOW"; do
    label="${pair%%|*}"; content="${pair#*|}"
    repo="$(fixture_repo "${label%% *}" "$TBL" "$ONE_ROW" "$content")"
    rc=$(cond_i "$repo")
    if [[ "$rc" -eq 0 ]] && ! grep -q 'Confirm on the terminal' "$TMP9/err"; then ok "b9 $label -> allow, no prompt (headless)"
    else no "b9 $label -> allow, no prompt" "rc=$rc err=$(cat "$TMP9/err")"; fi
done

# (F) the guard runs BEFORE the validator early exit: a missing validator with
# ONLY the table staged still blocks.
repo="$(fixture_repo F "$TBL" "$ONE_ROW" "$TWO_ROWS")"
rc=$( ( cd "$repo" && GOALFORGE_VALIDATE_SCRIPT=/nonexistent setsid -w bash "$HOOK" </dev/null >/dev/null 2>"$TMP9/err" ); echo $? )
if [[ "$rc" -eq 2 ]]; then ok "b9 F guard precedes the missing-validator early exit -> block"
else no "b9 F guard ordering" "rc=$rc err=$(cat "$TMP9/err")"; fi

# (G) a malformed index blob, through the real entry point: fail CLOSED (2),
# never the zero-breakage 0.
repo="$(fixture_repo G "$TBL" "$ONE_ROW" $'admitted: [unclosed\n')"
rc=$(cond_i "$repo")
if [[ "$rc" -eq 2 ]] && grep -q 'load failure' "$TMP9/err"; then ok "b9 G malformed staged table -> exit 2 with a load-failure reason (fail closed)"
else no "b9 G malformed staged table" "rc=$rc err=$(cat "$TMP9/err")"; fi

# Structural: the confirmation function reads ONLY the literal /dev/tty, with
# no expansion in any input redirect and no GOALFORGE_* read inside it; and it
# is defined unconditionally (no `declare -F ... ||` guard).
CONFIRM_BODY="$(awk '/^_gf_admitted_confirm\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$HOOK")"
REDIRECTS="$(grep -o '<[[:space:]]*[^[:space:]<]*' <<<"$CONFIRM_BODY" | sed 's/^<[[:space:]]*//' | sort -u)"
if [[ -n "$CONFIRM_BODY" && "$REDIRECTS" == "/dev/tty" ]] && ! grep -q 'GOALFORGE_' <<<"$CONFIRM_BODY" \
   && ! grep -qE 'declare -F[^|]*_gf_admitted_confirm' "$HOOK"; then
    ok "b9 structural: the confirmation reads only the literal /dev/tty, no GOALFORGE_*, defined unconditionally"
else
    no "b9 structural /dev/tty assertion" "redirects=[$REDIRECTS]"
fi

# (I) installed through scripts/goalforge-install-hooks.sh: a real `git commit`
# of fixture A through the installed .git/hooks/pre-commit is refused (HEAD
# unchanged) with the admitted-row diagnostic; a control commit of fixture D
# through the same installed hook succeeds.
INSTALLER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/goalforge-install-hooks.sh"
repo="$(fixture_repo I "$TBL" "$ONE_ROW" "$TWO_ROWS")"
env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash "$INSTALLER" "$repo" >/dev/null 2>"$TMP9/inst.err"
irc=$?
before="$("${GQ[@]}" -C "$repo" rev-parse HEAD)"
( cd "$repo" && setsid -w "${GQ[@]}" commit -qm "add admitted row" </dev/null >/dev/null 2>"$TMP9/err" )
crc=$?
after="$("${GQ[@]}" -C "$repo" rev-parse HEAD)"
if [[ "$irc" -eq 0 && "$crc" -ne 0 && "$before" == "$after" ]] && blocked_msg; then
    ok "b9 I installed hook refuses the fixture-A commit (installer exit 0, HEAD unchanged, admitted-row diagnostic)"
else
    no "b9 I installed hook refuses fixture A" "installer=$irc commit=$crc head-moved=$([[ "$before" == "$after" ]] && echo no || echo yes) err=$(cat "$TMP9/err" "$TMP9/inst.err")"
fi
"${GQ[@]}" -C "$repo" reset -q --hard
printf '# comment only\n%s' "$ONE_ROW" > "$repo/$TBL"
"${GQ[@]}" -C "$repo" add -A
( cd "$repo" && setsid -w "${GQ[@]}" commit -qm "comment only" </dev/null >/dev/null 2>"$TMP9/err" )
crc=$?
if [[ "$crc" -eq 0 && "$("${GQ[@]}" -C "$repo" rev-parse HEAD)" != "$before" ]]; then
    ok "b9 I control: a comment-only commit through the same installed hook succeeds"
else
    no "b9 I control commit" "commit=$crc err=$(cat "$TMP9/err")"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
