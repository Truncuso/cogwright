# Respec edge — spec-altitude loop-back

A learning that falsifies a requirement in an approved `spec.md` returns to
spec altitude through one declared edge. The stage only PROPOSES the revision;
a human ratifies it on `spec -> ready`, which is the feature's single
spec-approval gate for a first spec and a revision alike. It is the
spec-altitude twin of `redecompose/` (the WP-altitude loop-back): the same
pure-diff-then-route shape and the same supersede-in-place ledger.

## Respec edges

A feature past spec approval enters a respec through one of the existing
reverse rows of the `## Feature edges` table (`references/state-machine.md`),
each `reason_required: yes`:

- `ready -> spec`
- `active -> spec`
- `executing -> spec`
- `completed -> spec`

Take it with `goalforge-transition.sh <feature> spec --reason "<learning>"`.
A feature at `spec` means "a proposal awaits ratification"; the chain driver
routes it back into `goalforge-spec`. The only way on is `spec -> ready`.

## Proposal

The stage writes one proposal dir and never touches `spec.md`:

```
<feature>/respec/<YYYY-MM-DD>-<slug>/
  proposed-spec.md   a complete candidate spec.md
  diff.json          goalforge-respec-diff.sh spec.md proposed-spec.md
```

That is `respec/<YYYY-MM-DD>-<slug>/proposed-spec.md` under the feature dir.
Each goal facet the revision changes gets a row in the proposal's own
`## Goal Changelog` (add the H2 when absent), written by the one changelog
writer:

```bash
bash scripts/goalforge-goal-changelog.sh append <proposal>/proposed-spec.md <facet> "<old>" "<new>" --reason "<learning>"
```

For a first spec there is no approved content to protect: `spec.md` itself is
the proposal, written at `draft -> spec`, and no `respec/` dir exists.

## Diff buckets

`scripts/goalforge-respec-diff.sh <approved> <proposed>` is pure (no status
write, no file write) and emits one JSON object:

```json
{"unchanged":[id], "changed":[id], "dropped":[id], "added":[id],
 "ambiguous":[{"dropped":id, "added":id}], "goal_facets_changed":[facet]}
```

- The key is the `C<n>` id of each `### C<n>` subsection under
  `## Interface Contract`. Two bodies are equal iff their sha256 after the
  `goalforge-feature-hash.sh` slice normalization (trailing-whitespace-stripped,
  LF-normalized) is equal.
- `unchanged` — kept key, equal body. `changed` — kept key, any normalized-body
  difference. The script never judges whether new wording keeps the meaning;
  the human judges that at ratification.
- `dropped` / `added` — key only in the approved / only in the proposed spec.
- `ambiguous` — a dropped key and an added key with equal bodies (a renumber).
  Never auto-resolved; the human decides rename versus replace.
- `goal_facets_changed` — each frontmatter `goal.<facet>` that differs.

## Ratification marker

`RATIFIED` in the proposal dir, exactly one line:

```
ratified_by: human date=<YYYY-MM-DD> sha256=<sha256 of proposed-spec.md> diff_sha256=<sha256 of diff.json> base_sha256=<sha256 of spec.md as ratified> reply=<verbatim reply>
```

The stage writes it only inside the Step 3 `yes` branch of an attended run.
Under `SDD_AUTONOMY=unattended` the stage writes the proposal and parks; it
never writes `RATIFIED`. `date=` equals the proposal dir's `<YYYY-MM-DD>`.

## Order

1. `RATIFIED` (the human's `yes`).
2. `bash scripts/goalforge-respec-apply.sh <feature> <proposal>`.
3. `goalforge-transition.sh <feature> ready --from spec --mode human --reason "<ratification>"`.

## Apply

`goalforge-respec-apply.sh` is the only writer of a revised `spec.md`. It
refuses (exit 1, no write) when `RATIFIED` is absent or malformed (any of
`date=`, `sha256=`, `diff_sha256=`, `base_sha256=` missing), when `sha256=` or
`diff_sha256=` does not match the current bytes, when `spec.md` is neither the
applied state (`sha256=`) nor the ratified base (`base_sha256=`), or, from the
base, when a changed goal facet has no added `## Goal Changelog` row.

From the base it then takes `flock` on the feature's transition lock file (the
same lock `goalforge-transition.sh` holds while it writes a status) and holds
it through its last write, so no status write lands between the check and the
writes, and no supersede write reverts a concurrent status write. A
read-only pre-pass over every WP computes every remaining refusal before the
first write:

- **Unparseable slice.** `contract_slice` is read as a YAML flow list
  (`[C2, C3]`) or a block list (`contract_slice:` then `- C<n>` lines at any
  indent), items optionally quoted, a trailing ` # comment` stripped. A value
  that does not parse fully into `C<n>` ids refuses the apply, naming the WP
  (fail-closed: an unread slice never silently skips a WP).
- **In flight** (human ruling H2, "Refuse apply"). A WP at `hardened`,
  `executing` or `implemented` whose `contract_slice` names a `changed`,
  `dropped` or `ambiguous[].dropped` key refuses the apply, naming the WP.
  The renumber rule: an `ambiguous` pair's dropped id counts as affected for
  this refusal only; supersede and reharden still leave `ambiguous` keys
  untouched. The walk-back target is `ready`: the human walks each named WP
  back to `ready` (`goalforge-transition.sh <wp> ready --reason "<respec>"`)
  and reruns the apply, whose reharden step then writes that WP's durable
  evidence file.

Then, each step skip-if-present so a partial apply resumes:

1. **Supersede, never delete.** Each `verified` WP whose `contract_slice`
   names a `changed` or `dropped` key gains `superseded_by:` and a dated
   `## Supersession` note. It keeps `status: verified` and every prior file
   (`redecompose/SKILL.md`, dropped-verified). Never archived, never removed.
   On a later revision `superseded_by:` is rewritten to name the latest
   proposal, and the one `## Supersession` section keeps one note per
   proposal (a note already present for this proposal is skipped).
2. **Reharden evidence.** Each such `ready` WP gains
   `<wp>/reharden/<YYYY-MM-DD>-respec-<slug>.md` with
   `kind: execution-learning` and `locator:` the proposal's `diff.json`. The
   revert itself (`ready -> hardened --mode evidence`) runs at the next harden
   entry; re-promotion keeps its human gate.
3. **Copy** `proposed-spec.md` over `spec.md` byte for byte.

Every date the apply writes is `RATIFIED` `date=`, never the wall clock, so a
rerun on a later day finds its own effects. `ambiguous` keys are reported,
never acted on. A rerun on the applied state is an exit-0 no-op: the spec
copy is the last step, so `applied` means the WP steps already ran, and they
are skipped entirely (a WP whose status moved since is not touched). The apply
makes no status write and no transition, and prints a JSON report naming the
superseded and reharden WPs.

## Ledger

No new row type. Status rows stay in the transition ledger (schema.md § Transition ledger) (single writer
`goalforge-transition.sh`); goal rows come from `goalforge-goal-changelog.sh`;
the supersede marker is the `superseded_by:` + `## Supersession` shape of
`redecompose/`. The proposal dir (proposed-spec, diff, RATIFIED) is retained
after the apply as the record of what was ratified.

## Enforcement limit

The marker records, not proves, a human reply. `goalforge-transition.sh`
records `human_gated` but does not enforce it (`state-machine.md`, Feature
policy), and the sha256 bindings tie a ratification to the exact proposal,
diff and base bytes without proving who wrote the line. Enforcing
`--mode human` on `human_gated: yes` edges is tracked as an idea outside this
edge.
