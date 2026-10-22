# Harness dependencies

Every harness primitive goalforge uses is either **hard-required** (the run
cannot be trusted without it) or **degradable** (a named fallback exists and the
run says so). The closed vocabulary is `references/harness-primitives.txt`;
the `goalforge-harness-check` test suite fails when a stage `SKILL.md` or
`execute/references/dispatch-resolution.md` names a vocabulary primitive that
has no row below.

## Minimum floor

Two things, nothing else: native sub-agent dispatch (the **Agent tool**) and the
toolchain `scripts/goalforge-doctor.sh` hard-requires (`git python3 jq flock
timeout realpath tar`, plus PyYAML). Every other primitive degrades.

## Table

`Needs` names the primitive a derived row depends on (`-` for a primitive row);
a derived row is not an availability key, it follows its `Needs` primitive.

| Primitive | Kind | Availability | Class | Needs | Degrade path |
|---|---|---|---|---|---|
| `Agent tool` | session tool | declared in the availability file | hard-required | - | none: the floor; a run without native sub-agent dispatch exits non-zero |
| `Workflow tool` | session tool | declared in the availability file | degradable | - | batching degrades to the C5 single owner, or Agent-tool batches at one uniform effort; WARN: the per-agent effort knob is lost |
| `AskUserQuestion` | session tool | declared in the availability file | degradable | - | ask the question as plain session text and wait; unattended runs PARK with a handoff |
| `admitted non-native implement` | dispatch row | follows the Workflow tool | degradable | `Workflow tool` | refuse to the first native provider, WARN as a refused row already does (`execute/references/dispatch-resolution.md` §Admitted execution) |
| `git` | toolchain | probed (`command -v`) | hard-required | - | none: the floor |
| `python3` | toolchain | probed (`command -v`) | hard-required | - | none: the floor |
| `jq` | toolchain | probed (`command -v`) | hard-required | - | none: the floor |
| `flock` | toolchain | probed (`command -v`) | hard-required | - | none: the floor |
| `timeout` | toolchain | probed (`command -v`) | hard-required | - | none: the floor |
| `realpath` | toolchain | probed (`command -v`) | hard-required | - | none: the floor |
| `tar` | toolchain | probed (`command -v`) | hard-required | - | none: the floor |
| `PyYAML` | toolchain | probed (`python3 -c 'import yaml'`) | hard-required | - | none: the floor |

The Workflow row's fallback is the C5 default (one owner), so losing the tool
never blocks a WP; a later harness-neutral workflow runner rewrites that cell.

## Availability input and trust

`scripts/goalforge-harness-check.sh <availability-file>` reads
`<primitive>=present|absent` lines (`#` comments and blank lines skipped).
Toolchain primitives are always probed: an observed absence wins, and a line may
only force `absent`, never mask a missing tool. Session tools cannot be observed
from a script, so they are taken from the file, and an undeclared session tool
counts as absent. A repeated key is a usage error. Exit 0 clean or with WARN lines (a
degradable primitive is absent); exit 1 naming a missing hard-required primitive;
exit 2 on a usage error, malformed line or repeated key. Trust assumption: a declaration is
only as honest as its writer, so the execute entry step writes it from the
session's actual tool list and never copies a fixture.

## Usage sites

First site per primitive in the stage files at WP-13 time (a snapshot; the test
is authoritative): `Agent tool` wayfind/SKILL.md:263, dispatch-resolution.md:79;
`Workflow tool` execute/SKILL.md:61, run/SKILL.md:52, dispatch-resolution.md:80,119;
`AskUserQuestion` capture/SKILL.md:136, spec/SKILL.md:46, redecompose/SKILL.md:117;
`git` execute/SKILL.md:26, dispatch-resolution.md:139; `python3` execute/SKILL.md:57,
harden/SKILL.md:23, plan-index/SKILL.md:26. `jq flock timeout realpath tar PyYAML`
are named by no stage file today; they are in the vocabulary because the doctor
hard-requires them.
