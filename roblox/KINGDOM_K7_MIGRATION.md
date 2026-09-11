# Kingdom K7 — Migration Pressure Plug-in

K7 measures social/economic pressure to migrate without moving Agents or writing migration intent onto them.

## Dependency

K7 depends only on K0 Core. It does not require K1-K6.

## Output

Only under:

```text
Workspace/AstraKingdomState/K7Migration
```

Aggregate indicators:
- STAY / CONSIDER / REFUGE / LEAVE counts
- candidate count
- high-risk count
- average pressure
- maximum pressure
- settlement attraction
- migration state: `CALM | BUILDING | PRESSURED | EXODUS_RISK`
- semantic revision

## Hard boundaries

- no Agent movement
- no per-Agent migration attributes
- no Role/Goal/Planner/Skill mutation
- no stock mutation
- no WorldGrid/terrain/route ownership
- no WorldSim ownership

## Acceptance

```text
Workspace.AstraKingdomState.K7Migration.K7Status == "PASS"
```

Verifier snapshots authoritative stock plus each Agent's position, Role, survival needs, critical flag and Health before/after publish. Any movement or Agent-state mutation is a hard runtime error.
