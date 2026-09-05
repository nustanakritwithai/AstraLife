# HANDOFF — AstraLife P4–P8

Repository: `nustanakritwithai/AstraLife`

Authoritative roadmap: `ASTRALIFE_DEVELOPMENT_PLAN_V051_V10_TH.md`

Current integrated baseline after P3 merge:
- `main` commit: `f2f01aa7ba3c1ada2f1dc0591323690d9df08eb9`
- P0 Core Hardening: merged + verified
- P0.1 Knowledge Boundary: merged + verified
- P1 Structured Belief: merged + verified
- P2 Memory + Migration + Inspector: merged + post-merge verified
- P3 Predictive World Model: merged after full P0→P3 acceptance
- Last authoritative P3 pre-merge CI: run `33955625021` on head `0c3e2a0cbb78bd5454a77e7ce49008dc40f6860f` = PASS

## Rules the next agent must preserve

1. Start each implementation phase from the latest integrated `main`, not from an old stacked branch.
2. World Runtime remains authoritative for truth and state mutation.
3. Agents may use only their observation, memory, delivered messages, beliefs, and learned model state; no hidden-world leakage.
4. Provider proposes only. Validator accepts/rejects. Resolver mutates world state.
5. Belief is not truth. Preserve provenance, origin evidence, expiry, status, and loop protection.
6. Do not expose hidden chain-of-thought. Inspector may show structured observations, beliefs, plans, predictions, outcomes, summaries, and traces.
7. Any export/persistence addition must have a real restore test.
8. Every runtime PR must rerun the complete prior regression chain plus the new phase gate.
9. Never claim PASS from an older head after a new commit.
10. Do not merge a runtime PR until its current head has authoritative green CI and an integrator review.
11. Keep changes incremental. Do not replace the project with a new architecture or duplicate the runtime pipeline.
12. Do not begin the next phase until the current phase is integrated and post-merge smoke/regression passes on `main`.

## Current cognition loop

`Observe → Model → Predict → Plan → Act → Verify → Learn`

P3 now supplies the prediction/outcome/error/calibration layer. The next phase starts at executable planning.

---

# P4 — Executable Plans + Bounded Replanning

Dependency: integrated P3 `main`.

Goal: move from one-shot intent/action selection to explicit bounded plan steps that can be invalidated and replanned without loops or unbounded retries.

Required plan-step schema:

```text
stepId
actionType
target
preconditions
successCondition
timeoutTick
onFailure = REPLAN | RETRY_BOUNDED | ABORT
status
attemptCount
createdTick
lastValidatedTick
```

Required behavior:
- Planner produces a bounded executable plan rather than an unstructured action chain.
- Before every execution/retry, revalidate preconditions against the current Agent-observable state and current runtime constraints.
- If a target disappears or a precondition becomes false, invalidate that step.
- Replanning must have an explicit budget: max replans, max retries per step, and timeout.
- Old/stale provider output must not revive an invalidated plan.
- No executable code from provider fields; only runtime-known enums and structured data.
- Prediction records from P3 may inform expected duration/risk but must not become hidden truth.
- Inspector should show current plan, current step, status, retry/replan count, and last failure reason.

Acceptance gate: `PLAN-01`

Scenario:
1. Agent plans toward a known target.
2. Target disappears or becomes unavailable mid-plan.
3. Current step is invalidated.
4. Agent either replans within budget or aborts safely.
5. No infinite loop, stale action, duplicate execution, or out-of-budget retry.

P4 CI must run:
`P0 → P0.1 → P1 → P2 → P3 → P4`

Suggested branch after P3 post-merge gate:
`p4-executable-plans-bounded-replanning`

---

# P5 — Team Commitments + Cooperation Scenarios

Dependency: integrated P4.

Goal: cooperation emerges through proposals and explicit commitments rather than a central coordinator directly assigning goals.

TeamTask shape:

```text
taskId
proposerId
objective
location
requiredParticipants
materialNeeds
startWindow
deadlineTick
memberCommitments
completionEvidence
status
```

Task lifecycle:
`PROPOSED → RECRUITING → READY → IN_PROGRESS → COMPLETED`
with exits:
`FAILED / CANCELLED / EXPIRED`

Commitment rules:
- Each Agent independently ACCEPTs or DECLINEs.
- Coordinator/proposer cannot directly overwrite another Agent goal.
- Commitment is not contribution; reputation/skill credit requires resolver-confirmed contribution.
- Withdrawal/cancellation releases reservations and forces bounded adaptation.
- Prevent reputation farming through repeated OFFER/ACCEPT messages.
- World constraints should make cooperation useful naturally; do not add hidden team bonuses.

Acceptance gates:
- `TEAM-01`: member accepts then withdraws; team adapts/recruits/cancels and no reservation remains stuck.
- `ACT-01`: two agents contend for the final resource; no negative stock and no double-success.

Early ablation recommended:
- full system
- no-communication
- no-learning
- no-prediction
with paired seeds and same resource/provider budgets.

P5 CI:
`P0 → P0.1 → P1 → P2 → P3 → P4 → P5`

Suggested branch:
`p5-team-commitments-cooperation`

---

# P6 — Real Provider Bridge + Isolation

Dependency: P2 minimum, but integrate against completed P4/P5 before release.

Goal: connect real remote/model provider execution while preserving per-Agent isolation, stale-response protection, budgets, and deterministic runtime authority.

Required identity envelope:

```text
simulationId
runEpoch
agentId
sessionId
requestId
observationId
deadlineTick
```

Provider requirements:
- one isolated conversation/session per Agent
- no shared conversation history across Agents
- credentials never stored in HTML/save/export
- one active decision per Agent initially
- request queue/concurrency caps
- calls/minute, tokens/minute, tokens/call caps
- timeout/retry cap
- 429 handling with bounded jittered retry
- fallback reason and actual provider/model identifier recorded
- late, duplicate, wrong-agent, wrong-session, old-epoch responses rejected with no world mutation

Acceptance:
- `API-01`: wrong agent/session response rejected.
- `API-02`: duplicate and post-reset response cause at most one world effect; old epoch rejected.
- `API-03`: timeout/429/budget exhaustion produce bounded retries and correct trace/fallback.

Important: a mock provider PASS is not evidence that the real provider path works. Record an actual real-provider integration run separately when credentials/environment are available.

Suggested branch:
`p6-provider-bridge-isolation`

---

# P7 — Scheduler Scale + Persistence + Replay

Dependency: integrated P5/P6.

Goal: scale runtime scheduling and make the entire simulation resumable/replayable with deterministic checkpoints where defined.

Save envelope target:

```text
saveSchemaVersion
simulationId
runEpoch
tick
seed
rngState
worldState
agentPersistentStates
pendingCommitments
eventLogCursor
```

Requirements:
- save and restore world + all Agent persistent states
- restore increments/refreshes epoch so in-flight old responses cannot apply
- cancel old logical requests on restore and regenerate when necessary
- no duplicate action IDs across resume
- schema migration table and snapshot fixtures
- replay log records accepted provider decisions/responses and timing metadata needed for replay
- scheduler has bounded queue and fairness metrics
- measure p95/max wait and agents missing decisions within budget

Acceptance:
- `SAVE-01`: save → load → continue preserves identity, skill, belief, memory, world-model calibration, plan, commitment as applicable.
- `REPLAY-01`: replay from recorded decisions yields matching checkpoint state hashes.
- `REG-01`: existing 60-agent / 1000-tick gate remains green.

Suggested branch:
`p7-scheduler-persistence-replay`

---

# P8 — V1.0 Benchmark + Report

Dependency: integrated P7.

Goal: evaluate the completed system with held-out scenarios rather than tuning against the same seeds.

Initial evaluation protocol from roadmap:
- 20 agents
- 10 simulated days
- 5 tuning seeds
- 20 held-out seeds
- lock `dayTicks`, scenario version, provider settings, resource budget before held-out evaluation
- crashes count as failures; do not discard bad runs

Metrics:
- survival rate
- cooperation completion
- repeated failure rate
- prediction error / MAE; Brier score only for explicitly probabilistic predictions
- resource deprivation agent-ticks
- scheduler fairness: p95/max decision wait and missed decision budgets
- provider cost/budget usage

Ablations:
- full system
- no communication
- no learning
- no prediction

Target cooperation evidence from roadmap:
- mean survival gain at least 10 percentage points
- paired 95% confidence interval above zero on held-out seeds

Do not weaken thresholds after seeing results. If targets fail, report failure and analyze causes.

V1.0 report should include:
- exact commits
- scenario/version/config
- seeds
- provider identifiers and budgets
- acceptance runs
- held-out results
- limitations
- reproducible replay sample

Suggested branch:
`p8-v1-benchmark-report`

---

# Required working sequence for the next agent

```text
main (P0–P3 integrated)
↓
post-merge P3 smoke/regression on main
↓
new branch from main
↓
P4 implementation + full regression + PLAN-01
↓ merge
post-merge main gate
↓
new P5 branch from main
↓
P5 + TEAM-01 + ACT-01 + regression
↓ merge + main gate
↓
P6 provider isolation/bridge
↓ merge + main gate
↓
P7 scheduler/persistence/replay
↓ merge + main gate
↓
P8 held-out benchmark/report
```

Do not stack P4→P5→P6 branches before integration unless an explicit exception is documented and later retargeted cleanly.

## Current verified reference points

- P1 authoritative historical integration run: `33950943580`
- P2 pre-merge deep-review run: `33953318066`
- P2 post-merge main smoke: `33953762636`
- P3 authoritative current-head run before merge: `33955625021`
- P3 merged main commit: `f2f01aa7ba3c1ada2f1dc0591323690d9df08eb9`

## First action for the next agent

Do **not** start coding P4 immediately from an old local checkout. First:
1. fetch current `main`
2. verify `main` still points at or descends from `f2f01aa7...`
3. run or trigger P0→P3 post-merge smoke on `main`
4. only after it passes, create a fresh P4 branch from that exact `main`
5. implement P4 only

This document is a handoff/backlog PR. It contains no runtime implementation and may be merged independently.