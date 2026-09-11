# Kingdom K5 — Governance Advisory Plug-in

K5 turns current colony conditions into governance recommendations without owning money, taxes, laws, Agents, or world simulation.

## Dependency

K5 depends only on K0 Core. It does not require K1-K4 and does not depend on K6-K7.

## Output

Only under:

```text
Workspace/AstraKingdomState/K5Governance
```

Indicators:
- Legitimacy
- Prosperity / Unrest proxy
- Relief Need
- Security Need
- Infrastructure Need
- Suggested Tax Rate
- Suggested budget split: Security / Relief / Infrastructure / Administration
- Decision: STEADY / EMERGENCY_RELIEF / INCREASE_SECURITY / INVEST_INFRASTRUCTURE / REDUCE_PRESSURE / CONSOLIDATE_GROWTH

## Hard boundaries

- advisory only
- no treasury writer
- no tax collection
- no stock mutation
- no Agent state mutation
- no Goal/Planner/Role/Skill mutation
- no WorldSim ownership

## Acceptance

```text
Workspace.AstraKingdomState.K5Governance.K5Status == "PASS"
```

Verifier validates tax/budget bounds and compares authoritative stock plus Agent state before/after every publish.
