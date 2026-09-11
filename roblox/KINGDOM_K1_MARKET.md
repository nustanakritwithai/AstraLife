# Kingdom K1 — Market Economy Plug-in

K1 is a deterministic, read-only market projection derived from the stock-flow economy concepts in `Kingdom-sandbox`.

## Dependency

K1 depends only on K0 Core. It does not depend on K2 Labor, K3 Settlement, or any later Kingdom module.

## Input

Read-only through K0 `SourceReader`:
- colony Wood / Stone / Food / Water stock
- storage capacity
- population and survival-critical population
- structure count
- danger signal
- observed Agent/LivingWorld ticks

## Output

Only under:

```text
Workspace/AstraKingdomState/K1Market
```

Per resource:
- observed stock
- demand
- scarcity
- stock coverage
- raw price
- smoothed price
- volatility
- shortage flag
- critical-shortage flag

Aggregate:
- average scarcity
- average volatility
- trade health
- stress index
- market regime: `SURPLUS | BALANCED | TIGHT | CRISIS`
- semantic revision

## Rules

- deterministic; no RNG
- price smoothing is tick-based and only follows Agent `WorldTick`
- LivingWorld tick is observed but never used as an economic clock
- no stock mutation
- no inventory mutation
- no Agent Goal/Role/Skill mutation
- no terrain/grid/world simulation

## Acceptance

```text
Workspace.AstraKingdomState.K1Market.K1Status == "PASS"
```

Verifier checks price/scarcity bounds, finite values, state write boundary, stock projection, and confirms authoritative stock is unchanged before/after the K1 update.
