---
title: System One (snapwright) x wayfind/goalforge — integration analysis
type: analysis
date: 2026-09-22
status: draft
scope: cross-project — cogwright (goalforge/wayfind) x snapwright (System One)
supersedes: none
---

# System One (snapwright) x wayfind/goalforge — integration memo

Date: 2026-09-22. Author: orchestrator session (cogwright), analysis by dispatched opus agent, verified against code on branch `feat/goalforge-slim`. Human rulings recorded at the end.

## 1. snapwright status

- Code effectively empty: `src/snapwright/__init__.py` one line; `tests/` only `test_version.py`; `spikes/` only `.gitkeep`. No adapters, no Pydantic contract, no CLI.
- What exists is design: research corpus under `docs/analysis/` (TypeSafe docs, model landscape, use-case map, GLM-5.3 second opinion, fable advisor) and an 11-ticket wayfind map at `plans/snapwright/wayfind/map.md`.
- Resolved: name; own Python repo; `Request(state, questions[])` batch shape; caller-generated `call_id`; `score` never hard-gates; raw httpx over the TypeSafe SDK.
- Open frontier: ticket-01 (flagship consumer), ticket-03 (egress policy), both grilling, human-gated. Calibration bar (ticket-04) unresolved.
- Maturity: pre-v0 scaffold. v0 exit criterion: one advisory consumer measured on >=20 real cases beating a deterministic baseline.
- `docs/analysis/design-analysis/2026-09-19-use-case-map.md` in snapwright already enumerates most slots (V1-V6, J1-J5, R1-R4, Q1-Q3); this memo re-verifies them against current cogwright code.

## 2. Integration slots

| Slot | Signal today | System One (state, question) -> out | Cost | Quality | Risk | Seam |
|---|---|---|---|---|---|---|
| Verify gate C goal judge — REJECT | `agents/evaluation-expert.md`, role `wp-verify` = opus/high (tier-map.md:40) | `{goal, diff}` -> boolean per dimension | would cut most | blocked: rubric requires `file:line` evidence; System One returns none | only 3 `wp.verified` events as labels | verify/SKILL.md:80-85 |
| Gate C second opinion — REJECT | already `glm-5.3:cloud` via ollama, effort low, propose-only | `{verdict, diff}` -> supports/contradicts/silent | ~0, leg already local + cheap | marginal | disagreement must still escalate to human (verify:99-101) | dispatch.yaml:116-121 |
| Harden G3 panel sizing — REJECT | 3x panel iff `severity: HIGH && register: production`, pure frontmatter predicate | — | — | — | replacing a rung-1 predicate with a model is a regression | harden/SKILL.md:80-82 |
| Findings severity/type triage — CONFIRM (advisory) | reviewer prose; severities hand-assigned | `{finding_text, quoted_span, file}` -> Choice(type), Choice(severity) | small (re-rank, no call removed) | orders BLOCK-worthy findings first | label drift across WPs | harden/SKILL.md:75-84; verify/SKILL.md:67-78 |
| Route fast/standard/wave — REJECT | `goalforge-route.sh` deterministic (R1-R3/W1-W2 counts); only `borderline` defers | `{goal, scope}` -> Choice(route) | negligible volume | — | `route:` marked RETIRED in schema.md:126 while capture still stamps it (capture/SKILL.md:182-204) — contradiction to resolve first | route.sh:151-158 |
| Tier selection — REJECT | `ROLE_TIER` table + regex blast-radius, "no model in the loop" | — | — | — | determinism is the stated invariant | pick-agent.py:228-307 |
| Wayfind frontier ordering — CONFIRM | frontier = DAG computation; order is `LC_ALL=C sort`, pick = next unclaimed | `{destination, ticket question, resolved decisions}` -> Score(unblocking value) | ~0, saves wrong-order sessions | real gap: no ranking exists | preference leakage; must stay advisory | wayfind-frontier.sh:415-423; wayfind/SKILL.md:211 |
| Ticket dedup / blind-spot re-check — CONFIRM | human diffs fresh candidates against `findings/blind-spot-NN.md` by eye | pair `{candidate_question, existing_ticket_question}` -> boolean(same decision) | replaces manual diff | catches re-proposed tickets | cross-encoder, local | wayfind/SKILL.md:163-168 |
| Gate B pre-screen — CONFIRM (quality only) | reviewer reads whole diff | per-hunk hazard booleans -> pointer in brief | 0 saved (gate B always runs) | higher recall of shim-fixes | code egress -> local-only | verify/SKILL.md:67-78 |
| Calibration gating — PRECONDITION | none | — | — | — | nothing may gate before this exists | snapwright ticket-04 |

Label corpus measured: 400 rows in `plans/goalforge-overhaul/trace-events.jsonl` (173 `gate.result`, 21 `dispatch.completed`, 9 `second_opinion.ok`, 5 `harden.parked`); 465 severity tokens across 14 `findings.md`; 97 wayfind tickets across efforts. n~9 for gate-C disagreement is unusable; n~465 severity rows is a plausible first set.

Cross-cutting: published savings come from escalating a minority of traffic. goalforge's expensive legs (gate B, gate C judge) are unconditional, so a pre-filter buys quality, not cost, unless a gate becomes conditional. The current contract forbids that.

## 3. Ranked experiments

1. Finding severity + type triage (advisory re-rank). Labels: 465 severity-tagged rows in `plans/*/wp-*/findings.md` (real traces). Baseline: reviewer-assigned severity. Metric: per-class confusion + CRITICAL recall. Threshold: >=0.90 CRITICAL recall and <=10% CRITICAL false-negative before it reorders anything; never gates.
2. Wayfind frontier ordering over 97 tickets. Labels: which frontier ticket a session actually picked and whether its resolution unblocked >=1 dependent. Baseline: alphabetical order. Metric: Spearman vs realized pick order + count of "picked ticket produced no unblock". Threshold: beat alphabetical on >=20 historical picks.
3. Blind-spot candidate dedup (local cross-encoder). Labels: `findings/blind-spot-NN.md` triage verdicts plus existing ticket corpus. Baseline: embedding top-k shortlist. Metric: precision@1 on known re-proposals. Threshold: no false "duplicate" on an accepted candidate.

## 4. Web findings (provenance)

- RouteLLM: 95% of GPT-4 quality at 26% of GPT-4 calls; 14% when trained on LLM-judge labels — https://lmsys.org/blog/2024-07-01-routellm/ , https://arxiv.org/pdf/2406.18665
- FrugalGPT cascade: up to 98% cost cut at GPT-4-level accuracy — https://arxiv.org/abs/2305.05176
- Trust or Escalate: Mistral-7B judge resolves ~80% of pairwise cases under a provable >80% human-agreement floor — https://arxiv.org/pdf/2407.18370
- UCCI: raw confidence is a weak router signal; isotonic calibration is where the value is — https://arxiv.org/html/2605.18796
- Conformal cascade: distribution-free error guarantee replaces a tuned threshold — https://arxiv.org/html/2607.25018
- GenRM: generative verifiers beat discriminative ones on reasoning tasks — https://arxiv.org/abs/2408.15240
- PRM survey, step-level reranking in Best-of-N — https://arxiv.org/pdf/2510.08049
- Judge-to-classifier distillation approx. human-labeled quality — https://arxiv.org/abs/2406.17633 ; rationale distillation — https://arxiv.org/abs/2305.02301
- Reranker caveat: BM25+vector hybrid beats BGE reranking on ~30% of domains; most deployments have no eval set (vendor blog, unverified) — https://futureagi.com/blog/best-rerankers-for-rag-2026/
- Martian's 98% claim is vendor-reported, unverified.

Cost deltas above are qualitative; no token counts per gate were measured, only configured tiers.

## 5. Human rulings (2026-09-22)

- First experiment: severity re-rank (experiment 1). Advisory only, never gates.
- Gates stay unconditional for now (no ruling to make gate B conditional was given).
- Egress policy: NOT local-only. Remote (hosted) System One providers are permitted for diff, findings, and ticket text. Answers snapwright ticket-03 for the cogwright consumer.
- `route:` retired-vs-stamped contradiction: folded into the goalforge-overhaul lint WP (ticket-77 cluster).
- Frontier ordering: advisory score delegation ALLOWED (experiment 2 unblocked). Score stays advisory; the pick remains the human's.
