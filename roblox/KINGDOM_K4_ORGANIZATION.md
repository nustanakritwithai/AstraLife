# Kingdom K4 — Organization Aggregate Plug-in

K4 projects colony/organization health without creating Team AI or changing Agent roles.

## Dependency

K4 depends only on K0 Core. It does not require K1-K3 and does not depend on K5-K7.

## Input

Read-only through K0:
- population and survival-critical population
- Safety / Social / health aggregates
- stock reserves
- structure count
- current Agent Role distribution

## Output

Only under:

```text
Workspace/AstraKingdomState/K4Organization
```

Indicators:
- member count
- role counts
- reserve per member / reserve health
- infrastructure
- cohesion
- operational capacity
- role coverage
- reputation
- organization state: `CRITICAL | STRAINED | READY | STRONG`
- semantic revision

## Rules

- aggregate only
- no Team AI
- no role assignment/switching
- no Skill XP
- no stock mutation
- no WorldSim ownership

## Acceptance

```text
Workspace.AstraKingdomState.K4Organization.K4Status == "PASS"
```

Verifier compares authoritative stock and every Agent Role before/after K4 publishes.
