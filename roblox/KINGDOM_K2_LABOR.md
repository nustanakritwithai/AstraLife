# Kingdom K2 — Labor Market Plug-in

K2 projects labor shortages and wage premiums from current colony conditions without changing Agent roles or skills.

## Dependency

K2 depends only on K0 Core. It does not require K1 Market and does not depend on K3-K7.

## Input

Read-only through K0 `SourceReader`:
- Wood / Stone / Food / Water stock
- population and survival-critical population
- structure count
- danger signal

K2 intentionally does not read or write P7 Skill XP.

## Output

Only under:

```text
Workspace/AstraKingdomState/K2Labor
```

For `farmer`, `woodcutter`, `miner`, `crafter`:
- resource-pressure score
- units-per-capita observation
- target wage premium
- smoothed wage premium

Aggregate:
- highest-demand profession
- highest pressure
- highest wage premium
- average labor pressure
- semantic revision

## Rules

- advisory only
- no Role switching
- no profession assignment
- no Skill XP mutation
- no stock mutation
- no WorldSim ownership
- deterministic; no RNG

## Acceptance

```text
Workspace.AstraKingdomState.K2Labor.K2Status == "PASS"
```

Verifier captures authoritative stocks and every Agent `Role` before and after K2 publishes. Any mutation of either is a hard runtime error.
