# Kingdom K3 — Settlement Society State

K3 converts current colony facts into read-only settlement/social health indicators.

## Dependency

K3 depends only on K0 Core. It does not require K1 Market or K2 Labor and does not depend on K4-K7.

## Input

Read-only through K0 `SourceReader`:
- Food / Water / total stock and storage capacity
- population / survival-critical population
- average Safety / Social / health
- structure count
- danger signal

## Output

Only under:

```text
Workspace/AstraKingdomState/K3Settlement
```

Indicators:
- Food Security
- Water Security
- Storage Health
- Infrastructure
- Average Safety / Social / Health
- Danger
- Prosperity
- Stability
- Unrest
- Resilience
- settlement state: `CRISIS | FRAGILE | STABLE | PROSPEROUS`
- semantic revision

## Rules

- projection only
- no stock mutation
- no Agent needs/health/Role mutation
- no Goal/Planner mutation
- no WorldSim ownership
- deterministic; no RNG

## Acceptance

```text
Workspace.AstraKingdomState.K3Settlement.K3Status == "PASS"
```

Verifier snapshots authoritative stock plus `Role/Hunger/Thirst/Energy/Safety/Social/Health` for every Agent before and after K3 publishes. Any mutation is a hard runtime error.
