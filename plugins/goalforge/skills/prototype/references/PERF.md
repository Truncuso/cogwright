---
title: "Prototype — Perf branch discipline (benchmark study)"
---

# Perf branch (benchmark study)

A small **study**: measure rival implementations, don't argue about them. The
deliverable is a worth-it verdict backed by numbers.

1. **State the question as a measurable claim** — "impl B is ≥3× faster than
   baseline at 10⁶ rows", "memory stays flat as N grows". The success
   criteria ARE the thresholds; a perf spike without a threshold is
   sightseeing.
2. **Build 2+ rival implementations behind the same interface** — the current
   / naive version is always one of them (the baseline); an optimization
   without a baseline has no denominator.
3. **Correctness gate before timing:** all implementations must produce
   identical output on the study's inputs. A fast wrong answer wins nothing —
   benchmark results for divergent implementations are void.
4. **Benchmark harness:** realistic (or realistically shaped) data; input
   sizes swept across orders of magnitude (10³, 10⁴, 10⁵, …) to expose the
   **scaling curve** — the shape (flat / linear / quadratic / cliff) answers
   "does it scale", not a single point; warmup runs before measurement
   (JIT/cache); ≥5 repetitions, report **median + spread**, never a single
   run; measure memory too when the question involves it.
5. **Write PERF.md**: the question + thresholds; the answer up front ("B: 4.2×
   at 10⁶, linear; adopt" / "B: 1.15×, not worth the complexity; keep
   baseline"); the results table (impl × input size → median, spread); the
   observed scaling shape per impl; the **worth-it verdict** — speedup vs the
   complexity delta the faster impl would add (Principle 2: performance wins
   arguments, but the complexity must pay for itself); harness command so the
   study is re-runnable.

## Define the baseline reference

A result is only a result once it answers all four of these — a perf claim
missing any one of them is not yet measured:

- **Baseline** — against what implementation is this measured? The naive /
  current version, named explicitly (step 2's rival that everything else is
  compared to).
- **Cost function** — measured by what cost function? Wall-clock time,
  allocations, memory footprint, or some other named metric — pick before
  running, not after seeing which metric flatters the result.
- **Optimization target** — optimizing toward what? The measurable claim from
  step 1 (a threshold, a scaling shape), not "make it faster" — a target
  without a number can't be missed.
- **Algorithm comparison** — compared to which alternative algorithm? The
  other rival implementation(s) from step 2, by name, not a vague "the old
  way".
