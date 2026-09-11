# Kingdom K6 — Recruitment Demand Plug-in

K6 projects which colony roles are under-supplied without spawning Agents or changing roles.

## Dependency

K6 depends only on K0 Core. It does not require K1-K5 and does not depend on K7.

## Output

Only under:

```text
Workspace/AstraKingdomState/K6Recruitment
```

For Scout / Gatherer / Builder:
- current count
- target count
- context bonus
- need count

Aggregate:
- highest-need role
- total need
- urgency
- suggested recruitment offer
- semantic revision

## Hard boundaries

- no Agent spawn/delete
- no Role assignment/switching
- no Skill XP/learning
- no stock mutation
- no WorldSim ownership

## Acceptance

```text
Workspace.AstraKingdomState.K6Recruitment.K6Status == "PASS"
```

Verifier compares authoritative stock and the exact Agent-name → Role map before/after every publish. Any spawn, delete or reassignment is a hard runtime error.
