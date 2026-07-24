---
title: "Prototype — Logic branch discipline"
---

# Logic branch

1. **State the question** in a comment at the top of the harness file.
2. **Isolate the logic as a pure module** — reducer `(state, action) => state`,
   explicit state machine, or a small set of pure functions; no I/O, no
   terminal code inside it. The harness imports it; nothing flows back. This
   split is what makes the answer (and optionally the module) survive the
   spike.
3. **Build the smallest interactive terminal harness** over it: each tick
   clears the screen and re-renders one full frame — current state
   pretty-printed, then keyboard shortcuts (`[a] add  [t] tick  [q] quit`).
   The user drives the state model by hand; "wait, that shouldn't be
   possible" moments are the bugs in the *idea*, which is the point. When the
   run is unattended (dispatched spike), a scripted case-runner over the same
   pure module replaces the keyboard.
4. **One command to run** — wire it into the project's existing task runner
   (`pnpm <name>` / `make <name>` / `python <path>`); command at the top of
   LOGIC.md.
5. **Write LOGIC.md**: the question; the answer (one sentence up front); the
   evidence (cases pushed through + observed state); what was tried and
   rejected; whether the pure module is an absorb candidate; the decision
   this unblocks.
